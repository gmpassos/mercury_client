import 'dart:convert';
import 'dart:typed_data';

import 'package:mercury_client/mercury_client.dart';
import 'package:mercury_client/src/http_client_extension.dart';
import 'package:swiss_knife/swiss_knife.dart';
import 'package:test/test.dart';

/// Unit tests: no server (requests through [HttpClientRequesterSimulation]).
void main() {
  group('HttpMethod', () {
    test('getHttpMethod / getHttpMethodName', () {
      for (var m in HttpMethod.values) {
        expect(getHttpMethod(m.name), equals(m));
        expect(getHttpMethod(' ${m.name.toLowerCase()} '), equals(m));
        expect(getHttpMethodName(m), equals(m.name));
      }

      expect(getHttpMethod(null), isNull);
      expect(getHttpMethod(''), isNull);
      expect(getHttpMethod('FOO'), isNull);
      expect(getHttpMethod('FOO', HttpMethod.POST), equals(HttpMethod.POST));
      expect(getHttpMethodName(null, HttpMethod.PUT), equals('PUT'));
    });

    test('canHttpMethodHaveBody / methodAcceptsQueryString', () {
      expect(
        HttpMethod.values.where(canHttpMethodHaveBody),
        unorderedEquals([HttpMethod.POST, HttpMethod.PUT, HttpMethod.PATCH]),
      );
      expect(
        HttpMethod.values.where(methodAcceptsQueryString),
        unorderedEquals([HttpMethod.GET, HttpMethod.OPTIONS]),
      );
    });
  });

  test('buildURLWithQueryParameters', () {
    expect(
      buildURLWithQueryParameters('http://a.com/x', {}),
      equals('http://a.com/x'),
    );
    expect(
      buildURLWithQueryParameters('http://a.com/x', {'b': '2'}),
      equals('http://a.com/x?b=2'),
    );
    expect(
      buildURLWithQueryParameters('http://a.com/x?a=1', {'b': '2'}),
      equals('http://a.com/x?a=1&b=2'),
    );
    expect(
      buildURLWithQueryParameters('http://a.com/x?a=1#f', {'a': '3'}),
      equals('http://a.com/x?a=3#f'),
    );
    expect(
      buildURLWithQueryParameters('http://a.com/x#f', {
        'a': '1',
      }, removeFragment: true),
      equals('http://a.com/x?a=1'),
    );
  });

  group('HttpStatus / HttpError', () {
    HttpStatus status(int s) => HttpStatus('http://a/', 'http://a/', s);

    test('status helpers', () {
      expect(status(200).isOK, isTrue);
      expect(status(204).isStatusSuccessful, isTrue);
      expect(status(404).isStatusNotFound, isTrue);
      expect(status(403).isStatusForbidden, isTrue);
      expect(status(0).isStatusNetworkError, isTrue);
      expect(status(503).isStatusServerError, isTrue);
      expect(status(0).isError, isTrue);
      expect(status(302).isError, isFalse);
      expect(status(302).isOK, isFalse);
    });

    test('HttpError', () {
      var error = HttpError(
        'http://a/x',
        'http://a/x?y=1',
        401,
        '{"error":"invalid_grant"}',
        null,
      );

      expect(error.status, equals(401));
      expect(error.url, equals('http://a/x'));
      expect(error.requestedURL, equals('http://a/x?y=1'));
      expect(error.hasMessage, isTrue);
      expect(error.isStatusUnauthenticated, isTrue);
      expect(error.isError, isTrue);
      expect(error.isOAuthAuthorizationError, isTrue);
      expect(error.toString(), contains('401'));

      var other = HttpError(
        'http://a/',
        'http://a/',
        500,
        '{"error":"x"}',
        null,
      );
      expect(other.isOAuthAuthorizationError, isFalse);
    });
  });

  group('Credential', () {
    test('BasicCredential', () {
      var c = BasicCredential('joe', 'p4ss');
      expect(c.type, equals('Basic'));
      expect(c.usesAuthorizationHeader, isTrue);

      var header = c.buildAuthorizationHeaderLine();
      expect(header, startsWith('Basic '));
      expect(
        utf8.decode(base64Url.decode(header.substring(6))),
        equals('joe:p4ss'),
      );

      var fromBase64 = BasicCredential.base64(header.substring(6));
      expect(fromBase64.username, equals('joe'));
      expect(fromBase64.password, equals('p4ss'));

      var noPass = BasicCredential.base64(base64Url.encode(utf8.encode('x')));
      expect(noPass.username, equals('x'));
      expect(noPass.password, isEmpty);
    });

    test('BasicCredential.fromJSON', () {
      void check(Object? json, String? user, [String? pass]) {
        var c = BasicCredential.fromJSON(json);
        if (user == null) {
          expect(c, isNull, reason: '$json');
        } else {
          expect(c?.username, equals(user), reason: '$json');
          expect(c?.password, equals(pass), reason: '$json');
        }
      }

      check(['joe', 'p1'], 'joe', 'p1');
      check({'username': 'joe', 'password': 'p2'}, 'joe', 'p2');
      check({'email': 'a@b.c', 'token': 'p3'}, 'a@b.c', 'p3');
      check('joe:p4', 'joe', 'p4');
      check('joe p5', 'joe', 'p5');

      check(null, null);
      check(['joe'], null);
      check([1, 2], null);
      check({'username': 'joe'}, null);
      check({'a': 1, 'b': 2}, null);
      check('joe', null);
      check(123, null);
    });

    test('BearerCredential', () {
      var c = BearerCredential('TK');
      expect(c.type, equals('Bearer'));
      expect(c.usesAuthorizationHeader, isTrue);
      expect(c.buildAuthorizationHeaderLine(), equals('Bearer TK'));

      expect(
        BearerCredential.fromJSONToken({'access_token': 'A'})?.token,
        equals('A'),
      );
      expect(
        BearerCredential.fromJSONToken({'accessToken': 'B'})?.token,
        equals('B'),
      );
      expect(
        BearerCredential.fromJSONToken({
          'accessToken': {'token': 'C'},
        })?.token,
        equals('C'),
      );
      expect(
        BearerCredential.fromJSONToken({'access_token': 123})?.token,
        equals('123'),
      );
      expect(BearerCredential.fromJSONToken({'access_token': ' '}), isNull);
      expect(BearerCredential.fromJSONToken({'other': 'x'}), isNull);
      expect(BearerCredential.fromJSONToken('x'), isNull);
      expect(
        BearerCredential.fromJSONToken({'t': 'D'}, 't')?.token,
        equals('D'),
      );

      var json = {
        'a': {
          'b': ['x', 'y'],
        },
      };
      expect(BearerCredential.findToken(json, 'a/b/1'), equals('y'));
      expect(BearerCredential.findToken(json, 'a/c'), isNull);
      expect(BearerCredential.findToken(json, 'a'), isNull);
      expect(BearerCredential.findToken({}, 'a'), isNull);
      expect(BearerCredential.findToken(json, ''), isNull);
    });

    test('QueryStringCredential', () {
      var c = QueryStringCredential({'k': 'v'});
      expect(c.type, equals('queryString'));
      expect(c.usesAuthorizationHeader, isFalse);
      expect(c.buildAuthorizationHeaderLine(), isNull);
      expect(
        c.buildURL('http://a.com/x?y=1#f'),
        equals('http://a.com/x?y=1&k=v'),
      );
    });

    test('JSONBodyCredential', () {
      HttpRequestBody json(Object? o) => HttpRequestBody(o, 'application/json');

      var c = JSONBodyCredential('auth', 'S');
      expect(c.type, equals('jsonbody'));
      expect(c.field, equals('auth'));
      expect(c.usesAuthorizationHeader, isFalse);
      expect(c.buildAuthorizationHeaderLine(), isNull);
      expect(c.buildURL('http://a/'), equals('http://a/'));

      expect(
        jsonDecode(c.buildBody(HttpRequestBody(null, null)).contentAsString!),
        equals({'auth': 'S'}),
      );
      expect(
        jsonDecode(c.buildBody(json('{"a":1}')).contentAsString!),
        equals({'a': 1, 'auth': 'S'}),
      );

      // No field: the authorization merged into the body.
      var map = JSONBodyCredential(' ', {'auth': 'S'});
      expect(map.field, isNull);
      expect(
        jsonDecode(map.buildBody(json('{"a":1}')).contentAsString!),
        equals({'a': 1, 'auth': 'S'}),
      );
      expect(
        jsonDecode(map.buildBody(HttpRequestBody(null, null)).contentAsString!),
        equals({'auth': 'S'}),
      );

      var list = JSONBodyCredential('', ['S']);
      expect(
        jsonDecode(list.buildBody(json('[1]')).contentAsString!),
        equals([1, 'S']),
      );

      expect(() => map.buildBody(json('[1]')), throwsStateError);
      expect(() => list.buildBody(json('{"a":1}')), throwsStateError);
      expect(
        () => JSONBodyCredential('', 'S').buildBody(json('{"a":1}')),
        throwsStateError,
      );
    });
  });

  group('Authorization', () {
    test('static', () async {
      var c = BearerCredential('TK');
      var a = Authorization.fromCredential(c);

      expect(a.isStaticCredential, isTrue);
      expect(a.isCredentialResolved, isTrue);
      expect(a.resolvedCredential, same(c));
      expect(a.tryResolvedCredential, same(c));
      expect(a.usesAuthorizationHeader, isTrue);
      expect(a.isResolvingCredential, isFalse);
      expect(await a.resolveCredential(HttpClient('http://a/'), null), same(c));
      expect(a.copy().resolvedCredential, same(c));
      expect(a.toString(), contains('AuthorizationStatic'));
    });

    test('provider: resolved once, null credential', () async {
      var calls = 0;
      var a = Authorization.fromProvider((client, lastError) async {
        calls++;
        return null;
      });

      expect(a.isStaticCredential, isFalse);
      expect(a.isCredentialResolved, isFalse);
      expect(a.tryResolvedCredential, isNull);
      expect(() => a.resolvedCredential, throwsStateError);

      expect(await a.resolveCredential(HttpClient('http://a/'), null), isNull);
      expect(calls, equals(1));
      expect(a.copy().isCredentialResolved, isFalse);
      expect(a.toString(), contains('AuthorizationResolvable'));
    });
  });

  test('HttpRequest', () {
    var request = HttpRequest(
      HttpMethod.POST,
      'http://a/x',
      'http://a/x?y=1',
      queryParameters: {'y': '1'},
      requestHeaders: {'Accept': 'application/json'},
      sendData: 'abc',
    );

    expect(request.retries, equals(0));
    request.incrementRetries();
    expect(request.retries, equals(1));

    expect(request.headerAccept, equals('application/json'));
    expect(request.sendDataAsString, equals('abc'));

    var s = request.toString();
    expect(s, contains('method: HttpMethod.POST'));
    expect(s, contains('requestURL: http://a/x?y=1'));
    expect(s, contains('retries: 1'));
  });

  group('HttpBody', () {
    test('types', () {
      expect(HttpBody.from(null), isNull);

      var s = HttpBody.from('abc')!;
      expect(HttpBody.from(s), same(s));
      expect(s.isString, isTrue);
      expect(s.size, equals(3));
      expect(s.asString, equals('abc'));
      expect(s.asByteArray, equals(utf8.encode('abc')));
      expect(s.toString(), equals('abc'));

      var map = HttpBody.from({'a': 1})!;
      expect(map.isMap, isTrue);
      expect(map.asString, equals('{"a":1}'));
      expect(map.size, equals(7));

      var bytes = HttpBody.from(<int>[104, 105])!;
      expect(bytes.isBytesArray, isTrue);
      expect(bytes.size, equals(2));
      expect(bytes.asString, equals('hi'));
      expect(bytes.asByteBuffer!.lengthInBytes, equals(2));

      var buffer = HttpBody.from(Uint8List.fromList([104, 105]).buffer)!;
      expect(buffer.isByteBuffer, isTrue);
      expect(buffer.size, equals(2));
      expect(buffer.asString, equals('hi'));
      expect(buffer.asByteArray, equals([104, 105]));

      expect(() => HttpBody.from(Future.value(1)), throwsArgumentError);
    });

    test('async getters', () async {
      var s = HttpBody.from('abc')!;
      expect(await s.asStringAsync, equals('abc'));
      expect(await s.asByteArrayAsync, equals(utf8.encode('abc')));
      expect((await s.asByteBufferAsync)!.lengthInBytes, equals(3));
    });

    test('bytesToString: charsets', () {
      var latin = Uint8List.fromList(latin1.encode('ação'));
      var utf = Uint8List.fromList(utf8.encode('ação'));

      expect(
        HttpBody.bytesToString(
          utf,
          MimeType.parse('text/plain; charset=utf-8'),
        ),
        equals('ação'),
      );
      expect(
        HttpBody.bytesToString(
          latin,
          MimeType.parse('text/plain; charset=iso-8859-1'),
        ),
        equals('ação'),
      );

      // No charset: UTF-8, else LATIN-1.
      expect(HttpBody.bytesToString(utf), equals('ação'));
      expect(HttpBody.bytesToString(latin), equals('ação'));
    });
  });

  group('extensions', () {
    test('List<int>', () {
      var list = [104, 105];
      var u8 = list.toUint8List();
      expect(u8, isA<Uint8List>());
      expect(u8.toUint8List(), same(u8));
      expect(list.toByteBuffer().lengthInBytes, equals(2));
      expect(u8.toByteBuffer().asUint8List(), equals([104, 105]));

      expect(list.decodeUTF8(), equals('hi'));
      expect(list.decodeLATIN1(), equals('hi'));
      expect(latin1.encode('ç').decode(), equals('ç'));
      expect(utf8.encode('ç').decode(tryUTF8: false), equals('Ã§'));
    });

    test('String', () {
      expect('hi'.toUint8List(), equals([104, 105]));
      expect('ç'.toUint8List(encoding: latin1), equals([0xE7]));
      // Not encodable in LATIN-1: UTF-8.
      expect('€'.toUint8List(encoding: latin1), equals(utf8.encode('€')));
      expect('hi'.toByteBuffer().lengthInBytes, equals(2));
    });
  });

  group('HttpClient (simulation)', () {
    HttpClient newClient() {
      var simulation = HttpClientRequesterSimulation()
        ..replyGET(RegExp(r'/json'), '{"a":1}')
        // The query parameters are in the requested URL:
        ..simulateGET(
          RegExp(r'/params'),
          (url, params) => jsonEncode(Uri.parse(url).queryParameters),
        )
        ..replyPOST(RegExp(r'/post'), '{"posted":true}')
        ..replyPUT(RegExp(r'/put'), '{"put":true}')
        ..replyOPTIONS(RegExp(r'/options'), '{"options":true}')
        ..replyANY(RegExp(r'/any'), 'ANY');

      return HttpClient('http://localhost:8080/api/', simulation);
    }

    test('requests and JSON', () async {
      var client = newClient();
      expect(client.clientRequester, isA<HttpClientRequesterSimulation>());
      expect(client.isBaseUrlLocalhost(), isTrue);
      expect(client.toString(), contains('baseURL'));

      expect(await client.getJSON('json'), equals({'a': 1}));
      expect(
        await client.getJSON('params', parameters: {'x': '1'}),
        equals({'x': '1'}),
      );
      expect(
        await client.postJSON('post', body: {'a': 1}),
        equals({'posted': true}),
      );
      expect(
        await client.putJSON('put', body: {'a': 1}),
        equals({'put': true}),
      );
      expect(await client.optionsJSON('options'), equals({'options': true}));
      expect(
        await client.requestJSON(HttpMethod.GET, 'json'),
        equals({'a': 1}),
      );

      expect((await client.delete('any')).bodyAsString, equals('ANY'));
      expect((await client.patch('any')).bodyAsString, equals('ANY'));

      expect(client.get('none'), throwsA(anything));
    });

    test('URLs: base URL, base path and filter', () async {
      var client = newClient();

      expect(
        client.buildURL('x', false),
        equals('http://localhost:8080/api/x'),
      );
      // A full path: from the root of the base URL's host.
      expect(client.buildURL('/x', true), equals('http://localhost:8080/x'));
      expect(
        client.buildRequestURL(HttpMethod.GET, 'x', parameters: {'a': '1'}),
        equals('http://localhost:8080/api/x?a=1'),
      );

      var other = client.withBaseURL('http://example.com/');
      // Without the trailing `/`:
      expect(other.baseURL, equals('http://example.com'));
      expect(other.isBaseUrlLocalhost(), isFalse);

      var withPath = client.withBasePath('/v2/');
      expect(withPath.baseURL, contains('/v2'));

      client.authorization = Authorization.fromCredential(
        BearerCredential('T'),
      );
      expect(
        client
            .withBaseURL('http://b/', preserveAuthorization: true)
            .authorization,
        isNotNull,
      );
      expect(client.withBaseURL('http://b/').authorization, isNull);

      client.urlFilter = (url, queryParameters) => '$url-filtered';
      expect(client.buildURL('x', false), endsWith('x-filtered'));
    });

    test('HttpCall', () async {
      var client = newClient();

      var call = HttpCall<dynamic>(
        client: client,
        method: HttpMethod.GET,
        path: 'params',
      );
      expect(call.toString(), contains('params'));

      var response = await call.call({'a': 1, 'b': true});
      expect(response!.json, equals({'a': '1', 'b': 'true'}));

      var resolved = await call.callAndResolve({'c': 'x'});
      // A simulated response has no JSON `Content-Type`: its text.
      expect(resolved, equals('{"c":"x"}'));

      expect(HttpCall.toQueryParameters(null), isNull);
      expect(
        HttpCall.toQueryParameters({'a': 1, 'b': null}),
        equals({'a': '1', 'b': ''}),
      );
      expect(HttpCall.toQueryParameterValue([1, 2]), equals('1,2'));
    });

    test('HttpCache: limits and timeout', () async {
      var cache = HttpCache(maxCacheMemory: 10, timeout: Duration(seconds: 2));
      expect(cache.hasMaxCacheMemory, isTrue);
      expect(cache.maxCacheMemory, equals(1024 * 4));
      expect(cache.hasTimeout, isTrue);
      expect(cache.toString(), contains('HttpCache'));

      cache.maxCacheMemory = 0;
      expect(cache.hasMaxCacheMemory, isFalse);
      cache.timeout = Duration(milliseconds: 10);
      expect(cache.timeout, equals(Duration(seconds: 1)));
      cache.timeout = Duration.zero;
      expect(cache.hasTimeout, isFalse);

      var client = newClient();
      var r1 = await cache.get(client, 'json');
      expect(await cache.get(client, 'json'), same(r1));
      expect(await cache.getJSON(client, 'json'), equals({'a': 1}));
      expect(
        await cache.postJSON(client, 'post', body: '{}'),
        equals({'posted': true}),
      );

      expect(cache.cleanCacheTimedOut(Duration(hours: 1)), equals(0));
      // No limit: nothing to clean.
      expect(cache.cleanCache(0), equals(-1));
      expect(cache.cleanCache(1), greaterThan(0));
      expect(cache.calculateCacheUsedMemory(), equals(0));
    });
  });

  group('HttpRequester', () {
    test('config', () {
      var requester = HttpRequester(
        {
          'host': 'example.com',
          'secure': true,
          'method': 'post',
          'path': '/items/{{id}}',
          'parameters': {'a': '1'},
          'body_type': 'application/json',
          'body': '{"id":"{{id}}"}',
          'response_type': 'JSON',
        },
        {'id': '7'},
      );

      expect(requester.scheme, equals('https'));
      expect(requester.host, equals('example.com'));
      expect(requester.baseURL, equals('https://example.com/'));
      expect(requester.httpMethod, equals(HttpMethod.POST));
      expect(requester.path, equals('/items/7'));
      expect(requester.parameters, equals({'a': '1'}));
      expect(requester.bodyType, equals('application/json'));
      expect(requester.body, equals('{"id":"7"}'));
      expect(requester.responseType, equals('json'));
      expect(requester.httpClient, isNotNull);

      // A port only: the runtime host.
      var port = HttpRequester({'host': ':8081'});
      expect(port.host, endsWith(':8081'));
      expect(port.httpMethod, equals(HttpMethod.GET));
    });

    test('doRequestWithClient', () async {
      var simulation = HttpClientRequesterSimulation()
        ..replyGET(RegExp(r'/json'), '{"a":1}')
        ..replyGET(RegExp(r'/text'), 'hello');
      var client = HttpClient('http://example.com/', simulation);

      var json = HttpRequester({
        'host': 'example.com',
        'path': '/json',
        'response_type': 'json',
      });
      expect(await json.doRequestWithClient(client), equals({'a': 1}));

      var text = HttpRequester({'host': 'example.com', 'path': '/text'});
      expect(await text.doRequestWithClient(client), equals('hello'));

      var cached = HttpRequester(
        {'host': 'example.com', 'path': '/json', 'response_type': 'json'},
        null,
        HttpCache(),
      );
      expect(await cached.doRequestWithClient(client), equals({'a': 1}));
    });
  });
}
