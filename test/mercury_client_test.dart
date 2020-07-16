import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:mercury_client/mercury_client.dart';
import 'package:test/test.dart';

class TestServer {
  io.HttpServer server;

  Completer _serverOpen;

  int get port => server != null ? server.port : -1;

  bool get isOpen => _serverOpen != null ? _serverOpen.isCompleted : false;

  void waitOpen() async {
    if (isOpen) return;
    await _serverOpen.future;
  }

  void open() async {
    _serverOpen = Completer();

    server = await io.HttpServer.bind(
      io.InternetAddress.loopbackIPv4,
      9180,
    );

    print('Server running: $server at port: $port');

    _serverOpen.complete(true);

    await for (io.HttpRequest request in server) {
      var response =
          'Hello, world! Method: ${request.method} ; Path: ${request.uri}';

      var contentType = request.headers.contentType;

      if (contentType != null) {
        response += ' ; Content-Type: $contentType';
      }

      var body = await _decodeBody(contentType, request);

      if (body != null && body.isNotEmpty) {
        response += ' <$body>';
      }

      request.response.write(response);
      await request.response.close();
    }
  }

  Future<String> _decodeBody(
      io.ContentType contentType, io.HttpRequest r) async {
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

  void close() async {
    print('Closing server $server');
    await server.close(force: true);
  }
}

void main() {
  group('HttpClient', () {
    TestServer testServer;

    setUp(() {
      testServer = TestServer();
      testServer.open();
    });

    tearDown(() {
      testServer.close();
    });

    test('Method GET', () async {
      testServer.waitOpen();

      var client = HttpClient('http://localhost:${testServer.port}/tests');
      expect(client.baseURL, matches(RegExp(r'http://localhost:\d+/tests')));

      var response = await client.get('foo', parameters: {'a': '123'});

      expect(response.isOK, equals(true));

      expect(response.body,
          equals('Hello, world! Method: GET ; Path: /tests/foo?a=123'));
    });

    test('Method POST', () async {
      testServer.waitOpen();

      var client = HttpClient('http://localhost:${testServer.port}/tests');
      expect(client.baseURL, matches(RegExp(r'http://localhost:\d+/tests')));

      var response = await client.post('foo',
          parameters: {'á': '12 3', 'b': '456'},
          body: 'Boooodyyy!',
          contentType: 'application/json');

      expect(response.isOK, equals(true));

      expect(
          response.body,
          equals(
              'Hello, world! Method: POST ; Path: /tests/foo?%C3%A1=12+3&b=456 ; Content-Type: application/json <Boooodyyy!>'));
    });
  });
}
