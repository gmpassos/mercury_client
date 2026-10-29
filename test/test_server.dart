import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:stream_channel/stream_channel.dart';

class TestServer {
  io.HttpServer? server;

  Completer? _serverOpen;

  int get port => server != null ? server!.port : -1;

  bool get isOpen => _serverOpen != null ? _serverOpen!.isCompleted : false;

  Future<void> waitOpen() async {
    if (isOpen) return;
    await _serverOpen!.future;
  }

  Future<void> start() async {
    print('[SERVER] STARTING...');

    _serverOpen = Completer();

    server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 9180);

    print('[SERVER] STARTED>>> port: $port ; server: $server');

    _serverOpen!.complete(true);

    _processRequests();
  }

  void _processRequests() async {
    await for (io.HttpRequest request in server!) {
      if (request.method == 'OPTION') {
        await _processOptionRequest(request);
      } else {
        await _processTestRequest(request);
      }
    }
  }

  Future _processOptionRequest(io.HttpRequest request) async {
    request.response.statusCode = 204;
    _setResponseCORS(request);

    print('[SERVER] OPTION>>> ${request.uri}');

    await request.response.close();
  }

  /// The IDs already answered by `504-once`.
  final Set<String> _answered504 = {};

  Future _processTestRequest(io.HttpRequest request) async {
    var path = request.uri.path;

    if (path.endsWith('/options-echo') && request.method == 'OPTIONS') {
      // A CORS preflight (no `X-Test`) or the actual `OPTIONS` request.
      return _processTestRequestEcho(request);
    }

    if (request.method != 'OPTIONS') {
      if (path.endsWith('/echo')) {
        return _processTestRequestEcho(request);
      } else if (path.endsWith('/auth')) {
        // A `401` unless the credential is `Bearer GOOD`.
        if (request.headers.value('Authorization') != 'Bearer GOOD') {
          return _processTestRequestStatus(request, 401);
        }
        return _processTestRequestEcho(request);
      } else if (path.endsWith('/multi-header')) {
        return _processTestRequestMultiHeader(request);
      } else if (path.endsWith('/bytes')) {
        return _processTestRequestBytes(request);
      } else if (path.endsWith('/token')) {
        return _processTestRequestToken(request);
      } else if (path.endsWith('/504-once')) {
        // A `504` the first time for an `id`, then OK.
        var id = request.uri.queryParameters['id'] ?? '';
        if (_answered504.add(id)) {
          return _processTestRequestStatus(request, 504);
        }
        return _processTestRequestOK(request);
      }
    }

    if (request.method == 'GET' && request.uri.path.contains('404')) {
      return _processTestRequestStatus(request, 404);
    } else if (request.method == 'GET' && request.uri.path.contains('401')) {
      // `401-slow`: answered later (e.g. after another request's `401`).
      if (request.uri.path.contains('slow')) {
        await Future.delayed(Duration(milliseconds: 400));
      }
      return _processTestRequestStatus(request, 401);
    } else if (request.method == 'GET' && request.uri.path.contains('500')) {
      return _processTestRequestStatus(request, 500);
    } else {
      return _processTestRequestOK(request);
    }
  }

  /// Answers with the request: method, query parameters, the `Authorization`
  /// and `X-Test` headers, the `Content-Type` and the body (JSON).
  Future _processTestRequestEcho(io.HttpRequest request) async {
    var contentType = request.headers.contentType;
    var body = await _decodeBody(contentType, request);

    var response = jsonEncode({
      'method': request.method,
      'query': request.uri.queryParameters,
      'authorization': request.headers.value('Authorization'),
      'x-test': request.headers.value('X-Test'),
      'contentType': contentType?.mimeType,
      'body': body,
    });

    request.response.statusCode = 200;
    _setResponseCORS(request);
    request.response.headers.add(
      'Content-Type',
      'application/json',
      preserveHeaderCase: true,
    );
    request.response.write(response);
    await request.response.close();
  }

  /// Answers with the header `X-Multi` with 2 values.
  Future _processTestRequestMultiHeader(io.HttpRequest request) async {
    request.response.statusCode = 200;
    _setResponseCORS(request);
    request.response.headers.add('X-Multi', 'a');
    request.response.headers.add('X-Multi', 'b');
    request.response.headers.contentType = io.ContentType.text;
    request.response.write('multi');
    await request.response.close();
  }

  /// Answers with the request body bytes (`application/octet-stream`), and
  /// `?size=n`: `n` bytes (`i % 256`).
  Future _processTestRequestBytes(io.HttpRequest request) async {
    var bytes = <int>[];
    await for (var chunk in request) {
      bytes.addAll(chunk);
    }

    var size = int.tryParse(request.uri.queryParameters['size'] ?? '');
    if (size != null) {
      bytes = List<int>.generate(size, (i) => i % 256);
    }

    request.response.statusCode = 200;
    _setResponseCORS(request);
    request.response.headers.contentType = io.ContentType.binary;
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  }

  /// Answers with a token in the header `X-Access-Token`.
  Future _processTestRequestToken(io.HttpRequest request) async {
    request.response.statusCode = 200;
    _setResponseCORS(request);
    request.response.headers.add(
      'X-Access-Token',
      'TK-SERVER',
      preserveHeaderCase: true,
    );
    request.response.headers.add(
      'Content-Type',
      'text/plain',
      preserveHeaderCase: true,
    );
    request.response.write('token');
    await request.response.close();
  }

  Future _processTestRequestOK(io.HttpRequest request) async {
    var contentType = request.headers.contentType;
    var body = await _decodeBody(contentType, request);

    String response;
    String responseType;

    if (request.uri.path.endsWith('json')) {
      responseType = 'application/json';
      var json = {'parameters': request.uri.queryParameters};
      response = jsonEncode(json);
    } else {
      responseType = 'text/plain';

      response =
          'Hello, world! Method: ${request.method} ; Path: ${request.uri}';

      if (contentType != null) {
        response += ' ; Content-Type: $contentType';
      }

      if (body.isNotEmpty) {
        response += ' <$body>';
      }
    }

    var origin =
        request.headers['Origin'] ?? 'http://${request.headers.host}:$port/';

    print('[SERVER] RESPONSE[200]>>> origin: $origin ; body: $response');

    request.response.statusCode = 200;
    _setResponseCORS(request);

    request.response.headers.add(
      'Content-Length',
      response.length,
      preserveHeaderCase: true,
    );

    request.response.headers.add(
      'Content-Type',
      responseType,
      preserveHeaderCase: true,
    );

    request.response.write(response);

    await request.response.close();
  }

  Future _processTestRequestStatus(io.HttpRequest request, int status) async {
    var origin =
        request.headers['Origin'] ?? 'http://${request.headers.host}:$port/';

    print('[SERVER] RESPONSE[303]>>> origin: $origin');

    request.response.statusCode = status;
    _setResponseCORS(request);

    await request.response.close();
  }

  void _setResponseCORS(io.HttpRequest request) {
    var origin =
        request.headers['Origin'] ?? 'http://${request.headers.host}:$port/';

    request.response.headers.add(
      'Access-Control-Allow-Origin',
      origin,
      preserveHeaderCase: true,
    );

    request.response.headers.add(
      'Access-Control-Allow-Methods',
      'GET,HEAD,PUT,POST,PATCH,DELETE,OPTIONS',
    );
    request.response.headers.add('Access-Control-Allow-Credentials', 'true');

    request.response.headers.add(
      'Access-Control-Allow-Headers',
      'Content-Type, Access-Control-Allow-Headers, Authorization, x-ijt, X-Test',
    );
    request.response.headers.add(
      'Access-Control-Expose-Headers',
      'Content-Length, Content-Type, Last-Modified, X-Access-Token, X-Access-Token-Expiration, X-Multi',
    );
  }

  Future<String> _decodeBody(
    io.ContentType? contentType,
    io.HttpRequest r,
  ) async {
    if (contentType != null) {
      var charset = contentType.charset;

      if (charset != null) {
        charset = charset.trim().toLowerCase();

        if (charset == 'utf8' || charset == 'utf-8') {
          return utf8.decoder.bind(r).join();
        } else if (charset == 'latin1' ||
            charset == 'latin-1' ||
            charset == 'iso-8859-1') {
          return latin1.decoder.bind(r).join();
        }
      }
    }

    return latin1.decoder.bind(r).join();
  }

  Future<void> close() async {
    print('[SERVER] CLOSE>>> $server');
    await server!.close(force: true);

    server = null;
    _serverOpen = null;
  }
}

void hybridMain(StreamChannel channel) async {
  print('[VM:CHANNEL] hybridMain...');

  TestServer? testServer;

  var allMessages = [];

  await for (var msg in channel.stream) {
    allMessages.add(msg);
    var op = '$msg';

    print(
      '[VM:CHANNEL] OP MSG>>>> msg: $msg > op: $op >> allMessages: $allMessages',
    );

    switch (op) {
      case 'start':
        {
          testServer = TestServer();
          await testServer.start();
          channel.sink.add(true);
          break;
        }
      case 'wait':
        {
          await testServer!.waitOpen();
          channel.sink.add(testServer.port);
          break;
        }
      case 'close':
        {
          await testServer!.close();
          testServer = null;
          channel.sink.add(true);
          break;
        }
      case 'quit':
        {
          channel.sink.add(true);
          break;
        }
    }
  }

  if (testServer != null) {
    print('[VM:CHANNEL] closing...');
    await testServer.close();
  }
}
