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

    test('HttpStatus: 4xx errors', () {
      bool isError(int status) =>
          HttpStatus('http://localhost/', 'http://localhost/', status).isError;

      for (var status in [
        400, 401, 402, 403, //
        for (var s = 405; s <= 418; ++s) s,
        421, 422, 423, 424, 425, 426, 428, 431, 451,
      ]) {
        expect(isError(status), isTrue, reason: '$status');
      }

      // An absent resource, and too many requests: not errors.
      for (var status in [404, 429]) {
        expect(isError(status), isFalse, reason: '$status');
      }
    });

    test('Authorization.fromProvider: resolved again after a 401', () async {
      var calls = 0;
      var authorization = Authorization.fromProvider((client, lastError) async {
        calls++;
        return BearerCredential('token-$calls');
      });

      var client = HttpClient('http://localhost/');

      HttpError error(int status) => HttpError(
        'http://localhost/',
        'http://localhost/',
        status,
        'error',
        null,
      );

      var credential = await authorization.resolveCredential(client, null);
      expect((credential as BearerCredential).token, equals('token-1'));

      // Cached: no error, or an error that isn't a rejected credential.
      expect(
        await authorization.resolveCredential(client, null),
        same(credential),
      );
      expect(
        await authorization.resolveCredential(client, error(500)),
        same(credential),
      );
      expect(calls, equals(1));

      // A `401`: the credential was rejected, resolved again.
      var credential2 = await authorization.resolveCredential(
        client,
        error(401),
      );
      expect((credential2 as BearerCredential).token, equals('token-2'));
      expect(calls, equals(2));
      expect(authorization.resolvedCredential, same(credential2));
    });

    test('HttpRequest', () async {
      {
        var client = HttpClient('http://foo.com/');

        var request = HttpRequest(
          HttpMethod.GET,
          'http://foo.com/path',
          'https://foo.com/path',
          queryParameters: {'a': '1'},
          requestHeaders: {'X-Extra': '123'},
        );

        expect(request.url, equals('http://foo.com/path'));
        expect(request.requestURL, equals('https://foo.com/path'));
        expect(request.queryParameters, equals({'a': '1'}));
        expect(request.requestHeaders, equals({'X-Extra': '123'}));
        expect(request.sendData, isNull);
        expect(request.sendDataLength, isNull);
        expect(request.sendDataAsString, isNull);

        var request2 = request.copyWithAuthorization(
          client,
          Authorization.fromCredential(BasicCredential('joe', '123456')),
        );

        expect(request2.url, equals('http://foo.com/path'));
        expect(request2.requestURL, equals('http://foo.com/path?a=1'));
        expect(request2.queryParameters, equals({'a': '1'}));
        expect(
          request2.requestHeaders,
          equals({'Authorization': 'Basic am9lOjEyMzQ1Ng==', 'X-Extra': '123'}),
        );
        expect(request2.sendData, isNull);
        expect(request2.sendDataLength, isNull);
        expect(request2.sendDataAsString, isNull);
      }

      {
        var client = HttpClient('http://foo.com/');

        var request = HttpRequest(
          HttpMethod.GET,
          'http://foo.com/path',
          'http://foo.com/path',
          sendData: 'abcd',
        );

        expect(request.sendData, equals([97, 98, 99, 100]));
        expect(request.sendDataLength, equals(4));
        expect(request.sendDataAsString, 'abcd');
        expect(request.sendDataAsString!.length, equals(4));

        var request2 = request.copyWithAuthorization(
          client,
          Authorization.fromCredential(BasicCredential('joe', '123456')),
        );

        expect(request2.sendData, equals([97, 98, 99, 100]));
        expect(request2.sendDataLength, equals(4));
        expect(request2.sendDataAsString, 'abcd');
        expect(request2.sendDataAsString!.length, equals(4));
      }

      {
        var client = HttpClient('http://foo.com/');

        var request = HttpRequest(
          HttpMethod.GET,
          'http://foo.com/path',
          'http://foo.com/path',
          sendData: 'char utf-8: Đ!',
        );

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
            33,
          ]),
        );
        expect(
          latin1.decode(request.sendData as List<int>),
          equals('char utf-8: Ä!'),
        );
        expect(request.sendDataLength, equals(15));
        expect(request.sendDataAsString, 'char utf-8: Đ!');
        expect(request.sendDataAsString!.length, equals(14));

        var request2 = request.copyWithAuthorization(
          client,
          Authorization.fromCredential(BasicCredential('joe', '123456')),
        );

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
            33,
          ]),
        );
        expect(request2.sendDataLength, equals(15));
        expect(request2.sendDataAsString, 'char utf-8: Đ!');
        expect(request2.sendDataAsString!.length, equals(14));
      }

      {
        var request = HttpRequest(
          HttpMethod.GET,
          'http://foo.com/path',
          'http://foo.com/path',
          requestHeaders: {
            'X-Extra': 'xyz',
            'Content-Type': 'text/plain; charset=UTF-8',
          },
        );

        expect(request.requestHeaders?['X-Extra'], equals('xyz'));
        expect(
          request.requestHeaders?['Content-Type'],
          equals('text/plain; charset=UTF-8'),
        );
        expect(request.headerContentType, equals('text/plain; charset=UTF-8'));
        expect(request.headerContentTypeMimeType, equals('text/plain'));
        expect(request.headerContentTypeCharset, equals('UTF-8'));

        request.headerContentTypeMimeType = 'text/html';
        expect(request.headerContentType, equals('text/html; charset=UTF-8'));
        expect(request.headerContentTypeMimeType, equals('text/html'));
        expect(request.headerContentTypeCharset, equals('UTF-8'));

        request.headerContentTypeCharset = 'latin-1';
        expect(
          request.headerContentType,
          equals('text/html; charset=ISO-8859-1'),
        );
        expect(request.headerContentTypeMimeType, equals('text/html'));
        expect(request.headerContentTypeCharset, equals('ISO-8859-1'));

        request.headerContentType = null;
        expect(request.headerContentType, isNull);
        expect(request.headerContentTypeMimeType, isNull);
        expect(request.headerContentTypeCharset, isNull);
      }

      {
        var request = HttpRequest(
          HttpMethod.GET,
          'http://foo.com/path',
          'http://foo.com/path',
          requestHeaders: {'Content-Type': 'text/plain'},
        );

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

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );
      expect(client.baseURL, matches(RegExp(r'http://localhost:\d+/tests')));

      var progress = <String>[];

      var response = await client.get(
        'foo',
        parameters: {'a': '123'},
        progressListener: (request, loaded, total, ratio, upload) {
          progress.add('${upload ? 'upload' : 'download'}[$loaded/$total]');
        },
      );

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

      expect(
        response.bodyAsString,
        equals('Hello, world! Method: GET ; Path: /tests/foo?a=123'),
      );

      print('PROGRESS: $progress');

      expect(
        progress.firstWhereOrNull(
              (e) => e.contains('download[') && e.contains('/50]'),
            ) !=
            null,
        isTrue,
      );

      var response2 = await client.get(
        'foo',
        parameters: {'a': '22', 'b': null, 'c': '33'},
      );

      expect(response2.isOK, isTrue);
      expect(
        response2.bodyAsString,
        equals('Hello, world! Method: GET ; Path: /tests/foo?a=22&b&c=33'),
      );
    });

    test('HttpCache', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );

      var cache = HttpCache();

      var responseCached = cache.getCachedRequest(
        client,
        HttpMethod.GET,
        'foo',
        queryParameters: {'a': '123'},
      );

      expect(responseCached, isNull);

      var response = await cache.get(client, 'foo', parameters: {'a': '123'});

      expect(response.isOK, isTrue);
      expect(response.isNotOK, isFalse);
      expect(response.isError, isFalse);

      expect(
        response.bodyAsString,
        equals('Hello, world! Method: GET ; Path: /tests/foo?a=123'),
      );

      var responseCached2 = cache.getCachedRequest(
        client,
        HttpMethod.GET,
        'foo',
        queryParameters: {'a': '123'},
      );

      expect(responseCached2, isNotNull);

      expect(
        responseCached2!.bodyAsString,
        equals('Hello, world! Method: GET ; Path: /tests/foo?a=123'),
      );
    });

    test('HttpCache', () async {
      await testServerChannel.waitOpen();

      var httpRequester = HttpRequester({
        'httpMethod': 'GET',
        'scheme': 'http',
        'host': 'localhost:${testServerChannel.serverPort}',
        'path': 'tests/foo',
        'parameters': {'a': '456'},
      });

      expect(httpRequester.path, equals('tests/foo'));
      expect(httpRequester.parameters, equals({'a': '456'}));

      var body = await httpRequester.doRequest();

      expect(
        body,
        equals('Hello, world! Method: GET ; Path: /tests/foo?a=456'),
      );
    });

    test('Method GET - 404', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );
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

    test('Method GET - 401', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );

      var response = await client.get('foo/401');

      expect(response.isOK, isFalse);
      expect(response.isNotOK, isTrue);
      expect(response.isError, isTrue);
      expect(response.status, equals(401));

      expect(response.isStatusUnauthenticated, isTrue);
      expect(response.isStatusForbidden, isFalse);
      expect(response.isStatusError, isTrue);
      expect(response.isStatusAccessError, isTrue);
      expect(response.isStatusServerError, isFalse);
      expect(response.isStatusNetworkError, isFalse);
    });

    test('Method GET - 500', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );
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
                (e) => e.requestedURL,
                'requestedURL',
                contains('/foo/500'),
              ),
        ),
      );
    });

    test('Method POST', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.post(
        'foo',
        parameters: {'á': '12 3', 'b': '456'},
        body: 'Boooodyyy!',
        contentType: 'application/json',
      );

      expect(response.isOK, isTrue);

      expect(
        response.bodyAsString,
        equals(
          'Hello, world! Method: POST ; Path: /tests/foo?%C3%A1=12+3&b=456 ; Content-Type: application/json <Boooodyyy!>',
        ),
      );
    });

    test('Method PUT', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.put(
        'foo',
        parameters: {'á': '12 3', 'b': '456'},
        body: 'Boooodyyy!',
        contentType: 'application/json',
      );

      expect(response.isOK, isTrue);

      expect(
        response.bodyAsString,
        equals(
          'Hello, world! Method: PUT ; Path: /tests/foo?%C3%A1=12+3&b=456 ; Content-Type: application/json <Boooodyyy!>',
        ),
      );
    });

    test('Method PATH', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.patch(
        'foo',
        parameters: {'á': '12 3', 'b': '456'},
        body: 'Boooodyyy!',
        contentType: 'application/json',
      );

      expect(response.isOK, isTrue);

      expect(
        response.bodyAsString,
        equals(
          'Hello, world! Method: PATCH ; Path: /tests/foo?%C3%A1=12+3&b=456 ; Content-Type: application/json <Boooodyyy!>',
        ),
      );
    });

    test('Method PATH', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.delete(
        'foo',
        parameters: {'á': '12 3', 'b': '456'},
        body: 'Boooodyyy!',
        contentType: 'application/json',
      );

      expect(response.isOK, isTrue);

      expect(
        response.bodyAsString,
        equals(
          'Hello, world! Method: DELETE ; Path: /tests/foo?%C3%A1=12+3&b=456 ; Content-Type: application/json <Boooodyyy!>',
        ),
      );
    });

    test('Method POS: path pattern', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.post(
        'foo/{{id}}',
        parameters: {'á': '12 3', 'b': '456', 'id': '1001'},
        body: 'Body!',
        contentType: 'application/json',
      );

      expect(response.isOK, isTrue);

      expect(
        response.bodyAsString,
        equals(
          'Hello, world! Method: POST ; Path: /tests/foo/1001?%C3%A1=12+3&b=456&id=1001 ; Content-Type: application/json <Body!>',
        ),
      );
    });

    test('Method POST: raw bytes', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.post(
        'foo',
        body: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 0]),
      );

      expect(response.isOK, isTrue);

      expect(
        response.bodyAsString,
        equals(
          'Hello, world! Method: POST ; Path: /tests/foo <\x01\x02\x03\x04\x05\x06\x07\b\t\x00>',
        ),
      );
    });

    test('Method POST: JSON List<int>', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );
      expect(client.baseURL, matches(RegExp(r'^http://localhost:\d+/tests$')));

      var response = await client.post(
        'foo',
        body: [1, 2, 3, 4, 5, 6, 7, 8, 9, 0],
        contentType: 'json',
      );

      expect(response.isOK, isTrue);

      expect(
        response.bodyAsString,
        equals(
          'Hello, world! Method: POST ; Path: /tests/foo ; Content-Type: application/json <[1,2,3,4,5,6,7,8,9,0]>',
        ),
      );
    });

    test('Method GET: JSON response', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests/json',
      );
      expect(
        client.baseURL,
        matches(RegExp(r'^http://localhost:\d+/tests/json$')),
      );

      {
        var response1 = await client.get(
          'json',
          parameters: {'a': 11, 'b': 22, 'c': 'xyz'},
        );

        expect(response1.isOK, isTrue);
        expect(response1.isBodyTypeJSON, isTrue);
        expect(
          response1.json,
          equals({
            'parameters': {'a': '11', 'b': '22', 'c': 'xyz'},
          }),
        );

        var response2 = await client.getJSON(
          'json',
          parameters: {'a': 111, 'b': 222, 'c': 'wxyz'},
        );

        expect(
          response2,
          equals({
            'parameters': {'a': '111', 'b': '222', 'c': 'wxyz'},
          }),
        );
      }

      {
        client.jsonDecoder = (s) => jsonDecode(s.toUpperCase());

        var response1 = await client.get(
          'json',
          parameters: {'a': 11, 'b': 22, 'c': 'xyz'},
        );

        expect(response1.isOK, isTrue);
        expect(response1.isBodyTypeJSON, isTrue);
        expect(
          response1.json,
          equals({
            'PARAMETERS': {'A': '11', 'B': '22', 'C': 'XYZ'},
          }),
        );

        var response2 = await client.getJSON(
          'json',
          parameters: {'a': 111, 'b': 222, 'c': 'wxyz'},
        );

        expect(
          response2,
          equals({
            'PARAMETERS': {'A': '111', 'B': '222', 'C': 'WXYZ'},
          }),
        );
      }
    });
  });

  // Against the test server: what the server actually receives (`echo`).
  group('HttpClient (integration)', () {
    setUp(() async {
      await testServerChannel.initialize();
      await testServerChannel.start();
    });

    tearDown(() async {
      await testServerChannel.close();
    });

    Future<HttpClient> newClient() async {
      await testServerChannel.waitOpen();
      return HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );
    }

    test('credentials: header, query string and JSON body', () async {
      var client = await newClient();

      var basic = await client.getJSON(
        'echo',
        authorization: BasicCredential('joe', 'p4ss'),
      );
      expect(
        basic['authorization'],
        equals(BasicCredential('joe', 'p4ss').buildAuthorizationHeaderLine()),
      );

      var bearer = await client.getJSON(
        'echo',
        authorization: BearerCredential('TK1'),
      );
      expect(bearer['authorization'], equals('Bearer TK1'));

      var query = await client.getJSON(
        'echo',
        authorization: QueryStringCredential({'api_key': 'K1'}),
      );
      expect(query['authorization'], isNull);
      expect(query['query'], equals({'api_key': 'K1'}));

      var jsonBody = await client.postJSON(
        'echo',
        authorization: JSONBodyCredential('auth', 'S1'),
        body: {'a': 1},
      );
      expect(jsonBody['authorization'], isNull);
      expect(jsonDecode(jsonBody['body']), equals({'a': 1, 'auth': 'S1'}));

      // The client's authorization, for every request:
      client.authorization = Authorization.fromCredential(
        BearerCredential('TK2'),
      );
      var clientAuth = await client.getJSON('echo');
      expect(clientAuth['authorization'], equals('Bearer TK2'));
    });

    test('autoChangeAuthorizationToBearerToken', () async {
      var client = (await newClient()).autoChangeAuthorizationToBearerToken(
        'X-Access-Token',
      );
      expect(client.responseHeaderWithToken, equals('X-Access-Token'));

      var resolved = <Authorization?>[];
      client.authorizationResolutionInterceptor = resolved.add;

      var response = await client.get('token');
      expect(response.isOK, isTrue);
      expect(response.getResponseHeader('X-Access-Token'), equals('TK-SERVER'));

      // The token of the response, from now on:
      expect(client.authorization?.resolvedCredential, isA<BearerCredential>());
      var echo = await client.getJSON('echo');
      expect(echo['authorization'], equals('Bearer TK-SERVER'));
      expect(resolved, isNotEmpty);
    });

    test('headers: per request and requestHeadersBuilder', () async {
      var client = await newClient();

      var perRequest = await client.getJSON(
        'echo',
        headers: {'X-Test': 'request'},
      );
      expect(perRequest['x-test'], equals('request'));

      client.requestHeadersBuilder = (client, url) => {'X-Test': 'builder'};
      var built = await client.getJSON('echo');
      expect(built['x-test'], equals('builder'));
    });

    test('methods: PUT, PATCH and DELETE with a body', () async {
      var client = await newClient();

      for (var method in [
        HttpMethod.PUT,
        HttpMethod.PATCH,
        HttpMethod.DELETE,
      ]) {
        var response = await client.request(
          method,
          'echo',
          body: '{"m":"${method.name}"}',
          contentType: 'application/json',
        );
        expect(response.isOK, isTrue, reason: method.name);

        var echo = response.json;
        expect(echo['method'], equals(method.name));
        expect(echo['contentType'], equals('application/json'));
        expect(echo['body'], equals('{"m":"${method.name}"}'));
      }
    });

    test('interceptor and responseProcessor', () async {
      var client = await newClient();

      var interceptor = _TestInterceptor();
      client.interceptor = interceptor;
      expect(client.hasInterceptor, isTrue);

      var processed = <HttpResponse>[];
      var requests = <Object>[];
      client.responseProcessor = (client, request, response) {
        requests.add(request);
        processed.add(response);
      };

      var echo = await client.getJSON('echo');

      // The header added by the interceptor was sent:
      expect(echo['x-test'], equals('intercepted'));
      expect(interceptor.filteredResponses, equals(1));
      expect(processed, hasLength(1));

      // The platform's request (an `XMLHttpRequest` in a browser, the
      // response of `dart:io` in the VM):
      expect(requests, hasLength(1));
    });

    test('HttpCache: cached responses', () async {
      var client = await newClient();
      var cache = HttpCache(maxCacheMemory: 1024 * 64);

      expect(cache.getCachedRequest(client, HttpMethod.GET, 'echo'), isNull);

      var response1 = await cache.get(client, 'echo');
      expect(response1.isOK, isTrue);

      var cached = cache.getCachedRequest(client, HttpMethod.GET, 'echo');
      expect(cached, same(response1));

      var response2 = await cache.get(client, 'echo');
      expect(response2, same(response1));

      expect(cache.calculateCacheUsedMemory(), greaterThan(0));

      var json = await cache.getJSON(client, 'json', parameters: {'x': '1'});
      expect(
        json,
        equals({
          'parameters': {'x': '1'},
        }),
      );

      expect(cache.clearCache(), greaterThan(0));
      expect(cache.getCachedRequest(client, HttpMethod.GET, 'echo'), isNull);
    });

    test('HttpCache: a server error is not cached', () async {
      var client = await newClient();
      var cache = HttpCache();

      var response1 = await cache.get(client, '500');
      expect(response1.status, equals(500));
      expect(cache.getCachedRequest(client, HttpMethod.GET, '500'), isNull);

      var response2 = await cache.get(client, '500');
      expect(response2, isNot(same(response1)));
    });

    test('OPTIONS', () async {
      var client = await newClient();

      var response = await client.options(
        'options-echo',
        parameters: {'a': '1'},
      );
      expect(response.status, equals(200));
      expect(response.json['method'], equals('OPTIONS'));
      expect(response.json['query'], equals({'a': '1'}));
    });

    test('Basic credential: standard Base64 of UTF-8', () async {
      var client = await newClient();

      var credential = BasicCredential('jöe', 'p>>?€');
      var echo = await client.getJSON('echo', authorization: credential);

      var line = echo['authorization'] as String;
      expect(line, startsWith('Basic '));
      expect(
        utf8.decode(base64.decode(line.substring(6))),
        equals('jöe:p>>?€'),
      );
    });

    test(
      'Authorization.fromProvider: a 401 retried with the new credential',
      () async {
        var client = await newClient();

        var tokens = ['BAD', 'GOOD'];
        var calls = 0;
        client.authorization = Authorization.fromProvider(
          (client, lastError) async => BearerCredential(tokens[calls++]),
        );

        var response = await client.get('auth');
        expect(response.status, equals(200));
        expect(response.json['authorization'], equals('Bearer GOOD'));
        expect(calls, equals(2));
      },
      // Only the browser client retries a `401`.
      testOn: 'browser',
    );

    test('a response header with many values', () async {
      var client = await newClient();

      var response = await client.get('multi-header');
      expect(response.isOK, isTrue);
      expect(response.getResponseHeader('X-Multi'), equals('a, b'));
    });

    test('PATCH: parameters as a JSON body', () async {
      var client = await newClient();

      var response = await client.patch('echo', parameters: {'a': '1'});
      expect(response.json['method'], equals('PATCH'));
      expect(response.json['contentType'], equals('application/json'));
      expect(jsonDecode(response.json['body']), equals({'a': '1'}));
    });

    test('binary bodies and progress', () async {
      var client = await newClient();

      var all = Uint8List.fromList(List.generate(10, (i) => i));
      var view = Uint8List.sublistView(all, 2, 6);

      var echo = await client.post(
        'bytes',
        body: view,
        contentType: 'application/octet-stream',
      );
      expect(echo.body!.asByteArray, equals([2, 3, 4, 5]));

      var buffer = await client.put(
        'bytes',
        body: Uint8List.fromList([7, 8, 9]).buffer,
        contentType: 'application/octet-stream',
      );
      expect(buffer.body!.asByteArray, equals([7, 8, 9]));

      var progress = <(int?, int?, double?)>[];
      var response = await client.get(
        'bytes',
        parameters: {'size': '100000'},
        progressListener: (request, loaded, total, ratio, upload) {
          if (!upload) progress.add((loaded, total, ratio));
        },
      );
      expect(response.bodyLength, equals(100000));
      expect(response.body!.asByteArray![300], equals(300 % 256));

      expect(progress, isNotEmpty);
      for (var (loaded, total, ratio) in progress) {
        expect(total, anyOf(isNull, equals(100000)));
        if (ratio != null) {
          expect(ratio, inInclusiveRange(0, 1));
          expect(ratio, equals(loaded! / total!));
        }
      }
      expect(progress.last.$1, equals(100000));
    });
  });
}

/// Adds the header `X-Test` to every request, and counts the responses.
class _TestInterceptor extends HttpClientInterceptor {
  int filteredResponses = 0;

  @override
  String? filterRequest(
    HttpClient client,
    HttpMethod method,
    String url,
    Map<String, String>? headers,
  ) {
    headers?['X-Test'] = 'intercepted';
    return null;
  }

  @override
  HttpResponse? filterResponse(HttpClient client, HttpResponse response) {
    filteredResponses++;
    return null;
  }
}
