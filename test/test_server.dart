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

    server = await io.HttpServer.bind(
      io.InternetAddress.loopbackIPv4,
      9180,
    );

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

  Future _processTestRequest(io.HttpRequest request) async {
    if (request.method == 'GET' && request.uri.path.contains('404')) {
      return _processTestRequestStatus(request, 404);
    } else if (request.method == 'GET' && request.uri.path.contains('500')) {
      return _processTestRequestStatus(request, 500);
    } else {
      return _processTestRequestOK(request);
    }
  }

  Future _processTestRequestOK(io.HttpRequest request) async {
    var response =
        'Hello, world! Method: ${request.method} ; Path: ${request.uri}';

    var contentType = request.headers.contentType;

    if (contentType != null) {
      response += ' ; Content-Type: $contentType';
    }

    var body = await _decodeBody(contentType, request);

    if (body.isNotEmpty) {
      response += ' <$body>';
    }

    var origin =
        request.headers['Origin'] ?? 'http://${request.headers.host}:$port/';

    print('[SERVER] RESPONSE[200]>>> origin: $origin ; body: $response');

    request.response.statusCode = 200;
    _setResponseCORS(request);

    request.response.headers
        .add('Content-Length', response.length, preserveHeaderCase: true);
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

    request.response.headers
        .add('Access-Control-Allow-Origin', origin, preserveHeaderCase: true);

    request.response.headers.add('Access-Control-Allow-Methods',
        'GET,HEAD,PUT,POST,PATCH,DELETE,OPTIONS');
    request.response.headers.add('Access-Control-Allow-Credentials', 'true');

    request.response.headers.add('Access-Control-Allow-Headers',
        'Content-Type, Access-Control-Allow-Headers, Authorization, x-ijt');
    request.response.headers.add('Access-Control-Expose-Headers',
        'Content-Length, Content-Type, Last-Modified, X-Access-Token, X-Access-Token-Expiration');
  }

  Future<String> _decodeBody(
      io.ContentType? contentType, io.HttpRequest r) async {
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
        '[VM:CHANNEL] OP MSG>>>> msg: $msg > op: $op >> allMessages: $allMessages');

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
