import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:mercury_client/mercury_client.dart';
import 'package:test/test.dart';

abstract class TestServerChannel {
  Future<bool> initialize();

  Future<bool> start();

  Future<bool> waitOpen();

  Future<bool> close();

  int? get serverPort;
}

void doBasicTests(TestServerChannel testServerChannel) {
  print('+----------------------------------------------------------------');
  print('| ${testServerChannel.runtimeType}');
  print('+----------------------------------------------------------------');

  group('HttpClient', () {
    setUp(() async {
      await testServerChannel.initialize();
      await testServerChannel.start();
    });

    tearDown(() async {
      await testServerChannel.close();
    });

    test('HttpRequest', () async {
      {
        var client = HttpClient('http://foo.com/');

        var request = HttpRequest(
            HttpMethod.GET, 'http://foo.com/path', 'https://foo.com/path',
            queryParameters: {
              'a': '1'
            },
            requestHeaders: {
              'X-Extra': '123',
            });

        expect(request.url, equals('http://foo.com/path'));
        expect(request.requestURL, equals('https://foo.com/path'));
        expect(request.queryParameters, equals({'a': '1'}));
        expect(
            request.requestHeaders,
            equals({
              'X-Extra': '123',
            }));
        expect(request.sendData, isNull);
        expect(request.sendDataLength, isNull);
        expect(request.sendDataAsString, isNull);

        var request2 = request.copyWithAuthorization(client,
            Authorization.fromCredential(BasicCredential('joe', '123456')));

        expect(request2.url, equals('http://foo.com/path'));
        expect(request2.requestURL, equals('http://foo.com/path?a=1'));
        expect(request2.queryParameters, equals({'a': '1'}));
        expect(
            request2.requestHeaders,
            equals({
              'Authorization': 'Basic am9lOjEyMzQ1Ng==',
              'X-Extra': '123',
            }));
        expect(request2.sendData, isNull);
        expect(request2.sendDataLength, isNull);
        expect(request2.sendDataAsString, isNull);
      }

      {
        var client = HttpClient('http://foo.com/');

        var request = HttpRequest(
            HttpMethod.GET, 'http://foo.com/path', 'http://foo.com/path',
            sendData: 'abcd');

        expect(request.sendData, equals([97, 98, 99, 100]));
        expect(request.sendDataLength, equals(4));
        expect(request.sendDataAsString, 'abcd');
        expect(request.sendDataAsString!.length, equals(4));

        var request2 = request.copyWithAuthorization(client,
            Authorization.fromCredential(BasicCredential('joe', '123456')));

        expect(request2.sendData, equals([97, 98, 99, 100]));
        expect(request2.sendDataLength, equals(4));
        expect(request2.sendDataAsString, 'abcd');
        expect(request2.sendDataAsString!.length, equals(4));
      }

      {
        var client = HttpClient('http://foo.com/');

        var request = HttpRequest(
            HttpMethod.GET, 'http://foo.com/path', 'http://foo.com/path',
            sendData: 'char utf-8: Đ!');

        expect(
            request.sendData,
            equals([
              99,
              104,
              97,
              114,
              32,
              117,
              116,
              102,
              45,
              56,
              58,
              32,
              196,
              144,
              33
            ]));
        expect(latin1.decode(request.sendData as List<int>),
            equals('char utf-8: Ä!'));
        expect(request.sendDataLength, equals(15));
        expect(request.sendDataAsString, 'char utf-8: Đ!');
        expect(request.sendDataAsString!.length, equals(14));

        var request2 = request.copyWithAuthorization(client,
            Authorization.fromCredential(BasicCredential('joe', '123456')));

        expect(
            request2.sendData,
            equals([
              99,
              104,
              97,
              114,
              32,
              117,
              116,
              102,
              45,
              56,
              58,
              32,
              196,
              144,
              33
            ]));
        expect(request2.sendDataLength, equals(15));
        expect(request2.sendDataAsString, 'char utf-8: Đ!');
        expect(request2.sendDataAsString!.length, equals(14));
      }

      {
        var request = HttpRequest(
            HttpMethod.GET, 'http://foo.com/path', 'http://foo.com/path',
            requestHeaders: {
              'X-Extra': 'xyz',
              'Content-Type': 'text/plain; charset=UTF-8'
            });

        expect(request.requestHeaders?['X-Extra'], equals('xyz'));
        expect(request.requestHeaders?['Content-Type'],
            equals('text/plain; charset=UTF-8'));
        expect(request.headerContentType, equals('text/plain; charset=UTF-8'));
        expect(request.headerContentTypeMimeType, equals('text/plain'));
        expect(request.headerContentTypeCharset, equals('UTF-8'));

        request.headerContentTypeMimeType = 'text/html';
        expect(request.headerContentType, equals('text/html; charset=UTF-8'));
        expect(request.headerContentTypeMimeType, equals('text/html'));
        expect(request.headerContentTypeCharset, equals('UTF-8'));

        request.headerContentTypeCharset = 'latin-1';
        expect(
            request.headerContentType, equals('text/html; charset=ISO-8859-1'));
        expect(request.headerContentTypeMimeType, equals('text/html'));
        expect(request.headerContentTypeCharset, equals('ISO-8859-1'));

        request.headerContentType = null;
        expect(request.headerContentType, isNull);
        expect(request.headerContentTypeMimeType, isNull);
        expect(request.headerContentTypeCharset, isNull);
      }

      {
        var request = HttpRequest(
            HttpMethod.GET, 'http://foo.com/path', 'http://foo.com/path',
            requestHeaders: {'Content-Type': 'text/plain'});

        expect(request.requestHeaders?['Content-Type'], equals('text/plain'));
        expect(request.headerContentType, equals('text/plain'));
        expect(request.headerContentTypeMimeType, equals('text/plain'));
        expect(request.headerContentTypeCharset, isNull);

        request.headerContentTypeCharset = 'utf8';
        expect(request.headerContentType, equals('text/plain; charset=UTF-8'));

        request.headerContentTypeCharset = null;
        expect(request.headerContentType, equals('text/plain'));
      }
    });

    test('Method GET', () async {
      await testServerChannel.waitOpen();

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests');
      expect(client.baseURL, matches(RegExp(r'http://localhost:\d+/tests')));

      var progress = <String>[];

      var response = await client.get('foo', parameters: {'a': '123'},
          progressListener: (request, loaded, total, ratio, upload) {
        progress.add('${upload ? 'upload' : 'download'}[$loaded/$total]');
      });

      print('!!! response: $response');

      expect(response.isOK, isTrue);
      expect(response.isNotOK, isFalse);
      expect(response.isError, isFalse);

      expect(response.isStatusSuccessful, isTrue);
      expect(response.isStatusUnauthenticated, isFalse);
      expect(response.isStatusInList([200, 202]), isTrue);
      expect(response.isStatusInList([400, 404]), isFalse);
      expect(response.isStatusInRange(200, 299), isTrue);
      expect(response.isStatusInRange(400, 499), isFalse);
      expect(response.isStatusNotFound, isFalse);
      expect(response.isStatusForbidden, isFalse);
      expect(response.isStatusError, isFalse);
      expect(response.isStatusServerError, isFalse);
      expect(response.isStatusNetworkError, isFalse);
      expect(response.isStatusAccessError, isFalse);

      expect(response.bodyAsString,
          equals('Hello, world! Method: GET ; Path: /tests/foo?a=123'));

      print('PROGRESS: $progress');

      expect(
          progress.firstWhereOrNull(
                  (e) => e.contains('download[') && e.contains('/50]')) !=
              null,
          isTrue);

      var response2 = await client
          .get('foo', parameters: {'a': '22', 'b': null, 'c': '33'});

      expect(response2.isOK, isTrue);
      expect(response2.bodyAsString,
          equals('Hello, world! Method: GET ; Path: /tests/foo?a=22&b&c=33'));
    });

    test('HttpCache', () async {
      await testServerChannel.waitOpen();

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests');

      var cache = HttpCache();

      var responseCached = cache.getCachedRequest(client, HttpMethod.GET, 'foo',
          queryParameters: {'a': '123'});

      expect(responseCached, isNull);

      var response = await cache.get(client, 'foo', parameters: {'a': '123'});

      expect(response.isOK, isTrue);
      expect(response.isNotOK, isFalse);
      expect(response.isError, isFalse);

      expect(response.bodyAsString,
          equals('Hello, world! Method: GET ; Path: /tests/foo?a=123'));

      var responseCached2 = cache.getCachedRequest(
          client, HttpMethod.GET, 'foo',
          queryParameters: {'a': '123'});

      expect(responseCached2, isNotNull);

      expect(responseCached2!.bodyAsString,
          equals('Hello, world! Method: GET ; Path: /tests/foo?a=123'));
    });

    test('HttpCache', () async {
      await testServerChannel.waitOpen();

      var httpRequester = HttpRequester({
        'httpMethod': 'GET',
        'scheme': 'http',
        'host': 'localhost:${testServerChannel.serverPort}',
        'path': 'tests/foo',
        'parameters': {'a': '456'}
      });

      expect(httpRequester.path, equals('tests/foo'));
      expect(httpRequester.parameters, equals({'a': '456'}));

      var body = await httpRequester.doRequest();

      expect(
          body, equals('Hello, world! Method: GET ; Path: /tests/foo?a=456'));
    });

    test('Method GET - 404', () async {
      await testServerChannel.waitOpen();

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests');
      expect(client.baseURL, matches(RegExp(r'http://localhost:\d+/tests')));

      var response = await client.get('foo/404');

      expect(response.isOK, isFalse);
      expect(response.isNotOK, isTrue);
      expect(response.isError, isFalse);
      expect(response.status, equals(404));
      expect(response.isStatusNotFound, isTrue);

      expect(response.isStatusSuccessful, isFalse);
      expect(response.isStatusUnauthenticated, isFalse);
      expect(response.isStatusInList([200, 202]), isFalse);
      expect(response.isStatusInList([400, 404]), isTrue);
      expect(response.isStatusInRange(200, 299), isFalse);
      expect(response.isStatusInRange(400, 499), isTrue);
      expect(response.isStatusForbidden, isFalse);
      expect(response.isStatusError, isFalse);
      expect(response.isStatusServerError, isFalse);
      expect(response.isStatusNetworkError, isFalse);
      expect(response.isStatusAccessError, isFalse);

      expect(response.bodyAsString, isNull);

      var responseJSON = await client.getJSON('foo/404');
      expect(responseJSON, isNull);
    });

    test('Method GET - 500', () async {
      await testServerChannel.waitOpen();

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests');
      expect(client.baseURL, matches(RegExp(r'http://localhost:\d+/tests')));

      var response = await client.get('foo/500');

      expect(response.isOK, isFalse);
      expect(response.isNotOK, isTrue);
      expect(response.isError, isTrue);
      expect(response.status, equals(500));

      expect(response.isStatusSuccessful, isFalse);
      expect(response.isStatusUnauthenticated, isFalse);
      expect(response.isStatusInList([500, 503]), isTrue);
      expect(response.isStatusInList([400, 404]), isFalse);
      expect(response.isStatusInRange(200, 299), isFalse);
      expect(response.isStatusInRange(500, 599), isTrue);
      expect(response.isStatusForbidden, isFalse);
      expect(response.isStatusError, isTrue);
      expect(response.isStatusServerError, isTrue);
      expect(response.isStatusNetworkError, isFalse);
      expect(response.isStatusAccessError, isFalse);

      expect(response.bodyAsString, isNull);

      expect(
        client.getJSON('foo/500'),
        throwsA(
          isA<HttpError>()
              .having((e) => e.status, 'status', equals(500))
              .having(
                  (e) => e.requestedURL, 'requestedURL', contains('/foo/500')),
        ),
      );
    });

    test('Method POST', () async {
      await testServerChannel.waitOpen();

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests');
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.post('foo',
          parameters: {'á': '12 3', 'b': '456'},
          body: 'Boooodyyy!',
          contentType: 'application/json');

      expect(response.isOK, isTrue);

      expect(
          response.bodyAsString,
          equals(
              'Hello, world! Method: POST ; Path: /tests/foo?%C3%A1=12+3&b=456 ; Content-Type: application/json <Boooodyyy!>'));
    });

    test('Method PUT', () async {
      await testServerChannel.waitOpen();

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests');
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.put('foo',
          parameters: {'á': '12 3', 'b': '456'},
          body: 'Boooodyyy!',
          contentType: 'application/json');

      expect(response.isOK, isTrue);

      expect(
          response.bodyAsString,
          equals(
              'Hello, world! Method: PUT ; Path: /tests/foo?%C3%A1=12+3&b=456 ; Content-Type: application/json <Boooodyyy!>'));
    });

    test('Method PATH', () async {
      await testServerChannel.waitOpen();

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests');
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.patch('foo',
          parameters: {'á': '12 3', 'b': '456'},
          body: 'Boooodyyy!',
          contentType: 'application/json');

      expect(response.isOK, isTrue);

      expect(
          response.bodyAsString,
          equals(
              'Hello, world! Method: PATCH ; Path: /tests/foo?%C3%A1=12+3&b=456 ; Content-Type: application/json <Boooodyyy!>'));
    });

    test('Method PATH', () async {
      await testServerChannel.waitOpen();

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests');
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.delete('foo',
          parameters: {'á': '12 3', 'b': '456'},
          body: 'Boooodyyy!',
          contentType: 'application/json');

      expect(response.isOK, isTrue);

      expect(
          response.bodyAsString,
          equals(
              'Hello, world! Method: DELETE ; Path: /tests/foo?%C3%A1=12+3&b=456 ; Content-Type: application/json <Boooodyyy!>'));
    });

    test('Method POS: path pattern', () async {
      await testServerChannel.waitOpen();

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests');
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.post('foo/{{id}}',
          parameters: {'á': '12 3', 'b': '456', 'id': '1001'},
          body: 'Body!',
          contentType: 'application/json');

      expect(response.isOK, isTrue);

      expect(
          response.bodyAsString,
          equals(
              'Hello, world! Method: POST ; Path: /tests/foo/1001?%C3%A1=12+3&b=456&id=1001 ; Content-Type: application/json <Body!>'));
    });

    test('Method POST: raw bytes', () async {
      await testServerChannel.waitOpen();

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests');
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.post('foo',
          body: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 0]));

      expect(response.isOK, isTrue);

      expect(
          response.bodyAsString,
          equals(
              'Hello, world! Method: POST ; Path: /tests/foo <\x01\x02\x03\x04\x05\x06\x07\b\t\x00>'));
    });

    test('Method POST: JSON List<int>', () async {
      await testServerChannel.waitOpen();

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests');
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.post('foo',
          body: [1, 2, 3, 4, 5, 6, 7, 8, 9, 0], contentType: 'json');

      expect(response.isOK, isTrue);

      expect(
          response.bodyAsString,
          equals(
              'Hello, world! Method: POST ; Path: /tests/foo ; Content-Type: application/json <[1,2,3,4,5,6,7,8,9,0]>'));
    });

    test('Method GET: JSON response', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
          'http://localhost:${testServerChannel.serverPort}/tests/json');
      expect(client.baseURL,
          matches(RegExp(r'^http://localhost:\d+/tests/json$')));

      {
        var response1 = await client
            .get('json', parameters: {'a': 11, 'b': 22, 'c': 'xyz'});

        expect(response1.isOK, isTrue);
        expect(response1.isBodyTypeJSON, isTrue);
        expect(
            response1.json,
            equals({
              'parameters': {'a': '11', 'b': '22', 'c': 'xyz'}
            }));

        var response2 = await client
            .getJSON('json', parameters: {'a': 111, 'b': 222, 'c': 'wxyz'});

        expect(
            response2,
            equals({
              'parameters': {'a': '111', 'b': '222', 'c': 'wxyz'}
            }));
      }

      {
        client.jsonDecoder = (s) => jsonDecode(s.toUpperCase());

        var response1 = await client
            .get('json', parameters: {'a': 11, 'b': 22, 'c': 'xyz'});

        expect(response1.isOK, isTrue);
        expect(response1.isBodyTypeJSON, isTrue);
        expect(
            response1.json,
            equals({
              'PARAMETERS': {'A': '11', 'B': '22', 'C': 'XYZ'}
            }));

        var response2 = await client
            .getJSON('json', parameters: {'a': 111, 'b': 222, 'c': 'wxyz'});

        expect(
            response2,
            equals({
              'PARAMETERS': {'A': '111', 'B': '222', 'C': 'WXYZ'}
            }));
      }
    });
  });
}
