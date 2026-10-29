import 'dart:convert';
import 'dart:typed_data';

import 'package:mercury_client/mercury_client.dart';
import 'package:mercury_client/src/http_client_extension.dart';
import 'package:swiss_knife/swiss_knife.dart' show MimeType;
import 'package:test/test.dart';

/// A [HttpClientRequesterSimulation] that keeps the last [HttpRequest].
class _RecordingRequester extends HttpClientRequesterSimulation {
  HttpRequest? lastRequest;

  final List<HttpRequest> requests = [];

  int status = 200;

  @override
  Future<HttpResponse> doHttpRequest(
    HttpClient client,
    HttpRequest request,
    ProgressListener? progressListener,
    bool log,
  ) async {
    lastRequest = request;
    requests.add(request);
    return HttpResponse(
      request.method,
      request.url,
      request.requestURL,
      status,
      HttpBody.from('{"n":${requests.length}}'),
      responseHeaderGetter: (key) =>
          key.toLowerCase() == 'content-type' ? 'application/json' : null,
      jsonDecoder: client.jsonDecoder,
    );
  }
}

/// Regression tests (no server) of fixed bugs, and of APIs not covered by
/// the other tests.
void main() {
  group('HttpRequest.copyWithAuthorization', () {
    test('uses the new credential, not the rejected one', () {
      var client = HttpClient('http://foo.com/');

      var request = HttpRequest(
        HttpMethod.GET,
        'http://foo.com/a',
        'http://foo.com/a',
        requestHeaders: {'authorization': 'Bearer OLD', 'X-A': '1'},
      );

      var request2 = request.copyWithAuthorization(
        client,
        Authorization.fromCredential(BearerCredential('NEW')),
      );

      expect(
        request2.requestHeaders,
        equals({'Authorization': 'Bearer NEW', 'X-A': '1'}),
      );
      // The original request is not changed:
      expect(request.requestHeaders!['authorization'], equals('Bearer OLD'));
    });

    test('POST form: parameters stay in the body', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);

      await client.post('form', parameters: {'a': '1'});
      var request = requester.lastRequest!;
      expect(request.requestURL, equals('http://foo.com/form'));
      expect(request.sendDataAsString, equals('a=1'));

      var request2 = request.copyWithAuthorization(
        client,
        Authorization.fromCredential(BearerCredential('T')),
      );
      expect(request2.requestURL, equals('http://foo.com/form'));
      expect(request2.requestHeaders!['Authorization'], equals('Bearer T'));
    });

    test('keeps noQueryString', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);

      await client.request(
        HttpMethod.GET,
        'x',
        parameters: {'a': '1'},
        noQueryString: true,
      );
      var request = requester.lastRequest!;
      expect(request.noQueryString, isTrue);
      expect(request.requestURL, equals('http://foo.com/x'));

      var request2 = request.copyWithAuthorization(
        client,
        Authorization.fromCredential(BearerCredential('T')),
      );
      expect(request2.noQueryString, isTrue);
      expect(request2.requestURL, equals('http://foo.com/x'));
    });
  });

  group('HttpRequest headers', () {
    test('Content-Length: not with a chunked Transfer-Encoding', () {
      var chunked = HttpRequest(
        HttpMethod.POST,
        'http://foo.com/',
        'http://foo.com/',
        requestHeaders: {'Transfer-Encoding': 'Chunked'},
        sendData: 'abc',
      );
      expect(chunked.headerContentLength, isNull);

      var gzip = HttpRequest(
        HttpMethod.POST,
        'http://foo.com/',
        'http://foo.com/',
        requestHeaders: {'Transfer-Encoding': 'gzip'},
        sendData: 'abc',
      );
      expect(gzip.headerContentLength, equals('3'));

      var plain = HttpRequest(
        HttpMethod.POST,
        'http://foo.com/',
        'http://foo.com/',
        sendData: 'abc',
      );
      expect(plain.headerContentLength, equals('3'));
    });

    test('Content-Type mime-type and charset', () {
      var request = HttpRequest(
        HttpMethod.POST,
        'http://foo.com/',
        'http://foo.com/',
      );

      expect(request.headerContentType, isNull);
      expect(request.headerContentTypeMimeType, isNull);
      expect(request.headerContentTypeCharset, isNull);

      request.headerContentTypeCharset = 'utf8';
      expect(request.headerContentType, equals('text/plain; charset=UTF-8'));

      request.headerContentTypeMimeType = 'application/json';
      expect(
        request.headerContentType,
        equals('application/json; charset=UTF-8'),
      );
      expect(request.headerContentTypeMimeType, equals('application/json'));
      expect(request.headerContentTypeCharset, equals('UTF-8'));

      request.headerContentTypeCharset = 'latin1';
      expect(
        request.headerContentType,
        equals('application/json; charset=ISO-8859-1'),
      );

      request.headerContentTypeCharset = null;
      expect(request.headerContentType, equals('application/json'));

      request.headerContentTypeCharset = 'utf-16';
      expect(
        request.headerContentType,
        equals('application/json; charset=utf-16'),
      );

      request.headerContentTypeMimeType = 'text/html';
      expect(request.headerContentType, equals('text/html; charset=utf-16'));

      request.headerContentTypeMimeType = null;
      expect(request.headerContentType, isNull);

      request.headerContentType = 'text/css';
      expect(request.headerContentTypeCharset, isNull);
      request.headerContentTypeMimeType = 'text/xml';
      expect(request.headerContentType, equals('text/xml'));
    });

    test('POST form: a Content-Type in any case is kept', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);

      await client.post(
        'form',
        parameters: {'a': '1'},
        headers: {'content-type': 'application/x-www-form-urlencoded'},
      );
      expect(
        requester.lastRequest!.requestHeaders,
        isNot(contains('Content-Type')),
      );
      expect(
        requester.lastRequest!.headerContentType,
        equals('application/x-www-form-urlencoded'),
      );
    });

    test('PATCH: parameters as a JSON body, with a Content-Type', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);

      await client.patch('p', parameters: {'a': '1'});
      var request = requester.lastRequest!;
      expect(request.headerContentType, equals('application/json'));
      expect(request.sendDataAsString, equals('{"a":"1"}'));
    });
  });

  group('BasicCredential', () {
    test('standard Base64 of UTF-8', () {
      // `>>?` is encoded with `+`/`/` in standard Base64 (`-`/`_` URL-safe).
      var credential = BasicCredential('u', 'p>>?');
      var line = credential.buildAuthorizationHeaderLine();
      expect(line, equals('Basic ${base64.encode(utf8.encode('u:p>>?'))}'));
      expect(line, contains('/'));

      var unicode = BasicCredential('jöe', 'ç€');
      var encoded = unicode.buildAuthorizationHeaderLine().substring(6);
      expect(utf8.decode(base64.decode(encoded)), equals('jöe:ç€'));

      var decoded = BasicCredential.base64(encoded);
      expect(decoded.username, equals('jöe'));
      expect(decoded.password, equals('ç€'));
    });
  });

  group('URLs', () {
    test('buildURLWithQueryParameters: escaped path and repeated params', () {
      expect(
        buildURLWithQueryParameters('http://a.com/x%2Fy/z', {'b': '2'}),
        equals('http://a.com/x%2Fy/z?b=2'),
      );
      expect(
        buildURLWithQueryParameters('http://a.com/x?a=1&a=2', {'b': '2'}),
        equals('http://a.com/x?a=1&a=2&b=2'),
      );
      expect(
        buildURLWithQueryParameters('http://a.com:8080/x?a=1#f', {'a': '3'}),
        equals('http://a.com:8080/x?a=3#f'),
      );
      expect(
        buildURLWithQueryParameters('http://a.com/x#f', {
          'a': '3',
        }, removeFragment: true),
        equals('http://a.com/x?a=3'),
      );
    });

    test("the caller's parameters are not changed", () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);

      var parameters = {'b': '2'};
      await client.get('/a?x=1', parameters: parameters);
      expect(parameters, equals({'b': '2'}));
      expect(
        Uri.parse(requester.lastRequest!.requestURL).queryParameters,
        equals({'b': '2', 'x': '1'}),
      );

      // Unmodifiable maps:
      await client.get('/a?x=1', parameters: const {'c': '3'});
      expect(
        Uri.parse(requester.lastRequest!.requestURL).queryParameters,
        equals({'c': '3', 'x': '1'}),
      );

      var deleteParameters = Map<String, String?>.unmodifiable({'d': '4'});
      await client.delete('/a?x=1', parameters: deleteParameters);
      expect(
        Uri.parse(requester.lastRequest!.requestURL).queryParameters,
        equals({'d': '4', 'x': '1'}),
      );

      await client.post('/a?x=1', parameters: const {'e': '5'});
      expect(requester.lastRequest!.sendDataAsString, equals('e=5&x=1'));
    });

    test('requests: escaped path and repeated params', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com:8080/', requester);

      await client.get('items/a%2Fb', parameters: {'p': '1'});
      expect(
        requester.lastRequest!.requestURL,
        equals('http://foo.com:8080/items/a%2Fb?p=1'),
      );

      await client.get('items?x=1&x=2', parameters: {'p': '1'});
      expect(
        requester.lastRequest!.requestURL,
        equals('http://foo.com:8080/items?p=1&x=1&x=2'),
      );

      await client.request(
        HttpMethod.GET,
        'items/a%2Fb?x=1&x=2',
        parameters: {'p': '1'},
      );
      var uri = Uri.parse(requester.lastRequest!.requestURL);
      expect(uri.path, equals('/items/a%2Fb'));
      expect(uri.queryParametersAll['x'], equals(['1', '2']));
      expect(uri.queryParameters['p'], equals('1'));

      await client.post('items/a%2Fb?y=1', body: 'b');
      expect(
        requester.lastRequest!.requestURL,
        equals('http://foo.com:8080/items/a%2Fb?y=1'),
      );

      await client.post('items/a%2Fb', queryString: 'q=1');
      expect(
        requester.lastRequest!.requestURL,
        equals('http://foo.com:8080/items/a%2Fb?q=1'),
      );
    });

    test('queryString with a pattern', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);

      await client.post(
        'q',
        parameters: {'id': '7'},
        queryString: 'id={{id}}&x=1',
      );
      expect(
        requester.lastRequest!.requestURL,
        equals('http://foo.com/q?id=7&x=1'),
      );

      var url = client.buildRequestURL(
        HttpMethod.GET,
        'q',
        parameters: {'a': '1'},
        authorization: Authorization.fromCredential(
          QueryStringCredential({'k': 'K'}),
        ),
      );
      expect(Uri.parse(url).queryParameters, equals({'a': '1', 'k': 'K'}));
    });
  });

  group('HttpBody', () {
    test('a byte view: only its bytes', () {
      var all = Uint8List.fromList([1, 2, 3, 4, 5]);
      var view = Uint8List.sublistView(all, 1, 3);

      var body = HttpBody.from(view)!;
      expect(body.asByteBuffer!.asUint8List(), equals([2, 3]));
      expect(view.toByteBuffer().asUint8List(), equals([2, 3]));

      // All of a buffer: not copied.
      all.toByteBuffer().asUint8List()[0] = 9;
      expect(all[0], equals(9));
    });

    test('asBlob', () async {
      for (var content in <Object>[
        Uint8List.fromList([104, 105]).buffer,
        Uint8List.fromList([104, 105]),
        [104, 105],
        'hi',
      ]) {
        var blob = HttpBody.from(content)!.asBlob!;
        expect(blob.size(), equals(2), reason: '$content');
        expect(
          (await blob.readByteBuffer()).asUint8List(),
          equals([104, 105]),
          reason: '$content',
        );

        // A blob body:
        var blobBody = HttpBody.from(blob)!;
        expect(blobBody.isBlob, isTrue);
        expect(blobBody.asBlob, same(blob));
        expect(blobBody.size, equals(2));
        expect(await blobBody.asStringAsync, equals('hi'));
        expect(await blobBody.asByteArrayAsync, equals([104, 105]));
      }

      var mapBlob = HttpBody.from({'a': 1})!.asBlob!;
      expect(mapBlob.size(), equals('{"a":1}'.length));
    });

    test('createHttpBlob: many parts', () async {
      var blob = createHttpBlob([
        'ab',
        Uint8List.fromList([99]).buffer,
        Uint8List.fromList([0, 100, 0]).sublist(1, 2),
        [101],
      ], MimeType.parse('text/plain'))!;

      expect(blob.size(), equals(5));
      expect(
        utf8.decode((await blob.readByteBuffer()).asUint8List()),
        equals('abcde'),
      );
      expect(isHttpBlob(blob), isTrue);
      expect(isHttpBlob('x'), isFalse);
    });

    test('POST a blob', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);

      var blob = createHttpBlob(['blob!'], null)!;
      await client.post('b', body: blob, contentType: 'text/plain');
      expect(requester.lastRequest!.sendDataLength, equals(5));

      var bytes = Uint8List.fromList([1, 2, 3]);
      await client.post('b', body: bytes.buffer, contentType: 'image/png');
      expect(requester.lastRequest!.sendDataLength, equals(3));
      await client.put('b', body: bytes.buffer);
      expect(requester.lastRequest!.sendDataLength, equals(3));
    });
  });

  group('typed data (review of #12)', () {
    test('a Uint16List: its bytes, not truncated elements', () {
      var u16 = Uint16List.fromList([0x0102, 0x0304]);
      var bytes = Uint8List.view(u16.buffer);

      expect(u16.toByteBuffer().asUint8List(), equals(bytes));
      expect(u16.toUint8List(), equals(bytes));

      var body = HttpBody.from(u16)!;
      expect(body.size, equals(4));
      expect(body.asByteBuffer!.asUint8List(), equals(bytes));
      expect(body.asByteArray, equals(bytes));

      var view = Uint16List.sublistView(
        Uint16List.fromList([1, 0x0506, 3]),
        1,
        2,
      );
      expect(view.toByteBuffer().lengthInBytes, equals(2));
    });

    test('Content-Length of an Int16List: its bytes', () {
      var request = HttpRequest(
        HttpMethod.POST,
        'http://h/',
        'http://h/',
        sendData: Int16List.fromList([1, 2]),
      );
      expect(request.headerContentLength, equals('4'));
      expect(request.sendDataLength, equals(4));
    });

    test('createHttpBlob: a list of ints is bytes', () async {
      for (var content in <List>[
        <int>[1, 2, 3],
        <dynamic>[1, 2, 3],
      ]) {
        var blob = createHttpBlob(content, null)!;
        expect(
          (await blob.readByteBuffer()).asUint8List(),
          equals([1, 2, 3]),
          reason: '${content.runtimeType}',
        );
      }

      var parts = createHttpBlob([
        'a',
        [98, 99],
      ], null)!;
      expect(
        utf8.decode((await parts.readByteBuffer()).asUint8List()),
        equals('abc'),
      );
    });
  });

  group('HttpRequester', () {
    test('body is not lower-cased', () {
      var requester = HttpRequester({
        'host': 'localhost:8080',
        'method': 'post',
        'body': ' {"Name":"X"} ',
        'bodyType': 'json',
      });
      expect(requester.body, equals('{"Name":"X"}'));
      expect(requester.httpMethod, equals(HttpMethod.POST));
      expect(requester.baseURL, equals('http://localhost:8080/'));
    });

    test('body with a pattern', () {
      var requester = HttpRequester(
        {'host': ':8081', 'body': '{"Id":"{{id}}"}', 'secure': true},
        {'id': 'AbC'},
      );
      expect(requester.body, equals('{"Id":"AbC"}'));
      expect(requester.scheme, equals('https'));
      expect(requester.host, endsWith(':8081'));
    });
  });

  group('HttpCache', () {
    test('an expired entry is refreshed, and valid again', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);
      var cache = HttpCache(timeout: Duration(seconds: 1));

      Future<int> get() async => (await cache.getJSON(client, 'a'))['n'];

      expect(await get(), equals(1));
      expect(await get(), equals(1));

      await Future.delayed(Duration(milliseconds: 1100));
      expect(await get(), equals(2));
      // Valid again (it was always refreshed after the first expiry):
      expect(await get(), equals(2));
      expect(requester.requests.length, equals(2));
    });

    test('network and server errors are not cached', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);
      var cache = HttpCache();

      requester.status = 500;
      expect((await cache.get(client, 'a')).status, equals(500));
      requester.status = 0;
      expect((await cache.get(client, 'a')).status, equals(0));
      requester.status = 200;
      expect((await cache.get(client, 'a')).status, equals(200));
      expect((await cache.get(client, 'a')).status, equals(200));
      expect(requester.requests.length, equals(3));

      // A 404 is cached:
      requester.status = 404;
      expect((await cache.get(client, 'b')).status, equals(404));
      expect((await cache.get(client, 'b')).status, equals(404));
      expect(requester.requests.length, equals(4));
    });

    test('a response per credential', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);
      var cache = HttpCache();

      var a = BearerCredential('A');
      var b = BearerCredential('B');

      var ra = await cache.get(client, 'x', authorization: a);
      var rb = await cache.get(client, 'x', authorization: b);
      expect(identical(ra, rb), isFalse);
      expect(
        requester.requests.map((r) => r.requestHeaders?['Authorization']),
        equals(['Bearer A', 'Bearer B']),
      );

      // The same token (another instance): cached.
      var ra2 = await cache.get(
        client,
        'x',
        authorization: BearerCredential('A'),
      );
      expect(ra2, same(ra));
      expect(
        cache.getCachedRequest(client, HttpMethod.GET, 'x', authorization: b),
        same(rb),
      );

      // getURL forwards the authorization:
      await cache.getURL('y', httpClient: client, authorization: a);
      expect(
        requester.lastRequest!.requestHeaders!['Authorization'],
        equals('Bearer A'),
      );
    });

    test('a response per JSON body / query string credential', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);
      var cache = HttpCache();

      var a = await cache.post(
        client,
        'j',
        authorization: JSONBodyCredential('auth', {'token': 'A'}),
      );
      var b = await cache.post(
        client,
        'j',
        authorization: JSONBodyCredential('auth', {'token': 'B'}),
      );
      expect(identical(a, b), isFalse);

      var a2 = await cache.post(
        client,
        'j',
        authorization: JSONBodyCredential('auth', {'token': 'A'}),
      );
      expect(a2, same(a));

      var q1 = await cache.get(
        client,
        'q',
        authorization: QueryStringCredential({'k': '1'}),
      );
      var q2 = await cache.get(
        client,
        'q',
        authorization: QueryStringCredential({'k': '2'}),
      );
      expect(identical(q1, q2), isFalse);
      expect(requester.requests.length, equals(4));
    });

    test('a body changed by the caller: the entry is found', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);
      var cache = HttpCache();

      var body = <String, Object?>{'k': 'v1'};
      var r1 = await cache.post(client, 'b', body: body);
      body['k'] = 'v2';
      var r2 = await cache.post(client, 'b', body: {'k': 'v1'});
      expect(r2, same(r1));
      expect(requester.requests.length, equals(1));
    });

    test('getCachedRequest: not an expired entry', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);
      var cache = HttpCache(timeout: Duration(seconds: 1));

      await cache.get(client, 'e');
      expect(cache.getCachedRequest(client, HttpMethod.GET, 'e'), isNotNull);
      await Future.delayed(Duration(milliseconds: 1100));
      expect(cache.getCachedRequest(client, HttpMethod.GET, 'e'), isNull);
    });

    test('a body of any type', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);
      var cache = HttpCache(maxCacheMemory: 1024 * 1024);

      await cache.post(client, 'm', body: {'a': 1});
      await cache.post(client, 'l', body: [1, 2]);
      await cache.post(client, 'b', body: Uint8List(3));
      await cache.post(client, 'n', body: 123);
      expect(cache.calculateCacheUsedMemory(), greaterThan(0));
      expect(requester.requests.length, equals(4));

      await cache.post(client, 'n', body: 123);
      expect(requester.requests.length, equals(4));
    });

    test(
      "query parameters changed by the caller don't lose an entry",
      () async {
        var requester = _RecordingRequester();
        var client = HttpClient('http://foo.com/', requester);
        var cache = HttpCache();

        var parameters = <String, String?>{'a': '1'};
        var r1 = await cache.get(client, 'p', parameters: parameters);
        parameters['a'] = '2';
        var r1b = await cache.get(client, 'p', parameters: {'a': '1'});
        expect(r1b, same(r1));
      },
    );

    test('memory limit: the largest removed first', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);
      var cache = HttpCache(maxCacheMemory: 4096);

      await cache.post(client, 'big', body: 'x' * 3000);
      await cache.post(client, 'small', body: 's');
      var used = cache.calculateCacheUsedMemory();
      expect(used, greaterThan(3000));

      await cache.post(client, 'big2', body: 'y' * 2000);
      expect(cache.calculateCacheUsedMemory(), lessThanOrEqualTo(4096));
      expect(
        cache.getCachedRequest(
          client,
          HttpMethod.POST,
          'big',
          body: 'x' * 3000,
        ),
        isNull,
      );
      expect(
        cache.getCachedRequest(client, HttpMethod.POST, 'small', body: 's'),
        isNotNull,
      );

      expect(cache.clearCache(), greaterThan(0));
      expect(cache.calculateCacheUsedMemory(), equals(0));
    });

    test('methods', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);
      var cache = HttpCache(verbose: true);

      expect((await cache.head(client, 'h')).method, equals(HttpMethod.HEAD));
      expect(
        (await cache.options(client, 'o')).method,
        equals(HttpMethod.OPTIONS),
      );
      expect(
        (await cache.put(client, 'p', body: 'x')).method,
        equals(HttpMethod.PUT),
      );
      expect(await cache.requestJSON(client, HttpMethod.GET, 'j'), isA<Map>());
      expect(await cache.optionsJSON(client, 'oj'), isA<Map>());
      expect(await cache.postJSON(client, 'pj', body: 'x'), isA<Map>());
      expect(await cache.putJSON(client, 'uj', body: 'x'), isA<Map>());
      expect(requester.requests.length, equals(7));

      // All cached:
      await cache.putJSON(client, 'uj', body: 'x');
      await cache.head(client, 'h');
      expect(requester.requests.length, equals(7));

      var httpRequester = HttpRequester(
        {'host': 'foo.com', 'path': '/r', 'responseType': 'json'},
        null,
        cache,
      );
      expect(await httpRequester.doRequestWithClient(client), equals({'n': 8}));
      expect(await httpRequester.doRequestWithClient(client), equals({'n': 8}));
    });

    test('stale response', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);
      var cache = HttpCache(timeout: Duration(seconds: 1));

      await cache.get(client, 's');
      await Future.delayed(Duration(milliseconds: 1100));

      HttpResponse? stale;
      var fresh = await cache.get(
        client,
        's',
        onStaleResponse: (r) => stale = r,
      );
      expect(stale, isNotNull);
      expect(stale!.json['n'], equals(1));
      expect(fresh.json['n'], equals(2));

      await Future.delayed(Duration(milliseconds: 1100));

      // The response arrives before the delay: no stale response.
      HttpResponse? stale2;
      await cache.get(
        client,
        's',
        onStaleResponse: (r) => stale2 = r,
        staleResponseDelay: Duration(seconds: 5),
      );
      expect(stale2, isNull);

      expect(cache.cleanCacheTimedOut(Duration(milliseconds: 1)), equals(0));
      await Future.delayed(Duration(milliseconds: 20));
      expect(
        cache.cleanCacheTimedOut(Duration(milliseconds: 1)),
        greaterThan(0),
      );
    });
  });

  group('HttpResponse / HttpError', () {
    test('status helpers through WithHttpStatus', () {
      var error = HttpError('http://a/', 'http://a/?x', 403, 'm', null);
      expect(error.isError, isTrue);
      expect(error.isNotOK, isTrue);
      expect(error.isOK, isFalse);
      expect(error.isStatus(403), isTrue);
      expect(error.isStatusAccessError, isTrue);
      expect(error.isStatusError, isTrue);
      expect(error.isStatusForbidden, isTrue);
      expect(error.isStatusInList([403]), isTrue);
      expect(error.isStatusInRange(400, 499), isTrue);
      expect(error.isStatusNetworkError, isFalse);
      expect(error.isStatusNotFound, isFalse);
      expect(error.isStatusRedirect, isFalse);
      expect(error.isStatusServerError, isFalse);
      expect(error.isStatusSuccessful, isFalse);
      expect(error.isStatusUnauthenticated, isFalse);
      expect(error.requestedURL, equals('http://a/?x'));
      expect(error.url, equals('http://a/'));
      expect(error.status, equals(403));
    });

    test('getters', () {
      var headers = {'location': 'http://b/', 'content-type': 'text/plain'};
      var response = HttpResponse(
        HttpMethod.GET,
        'http://a/',
        'http://a/',
        302,
        HttpBody.from('body'),
        responseHeaderGetter: (k) => headers[k.toLowerCase()],
      );

      expect(response.isStatusRedirect, isTrue);
      expect(response.redirectToLocation, equals('http://b/'));
      expect(response.bodyType, equals('text/plain'));
      expect(response.isBodyTypeJSON, isFalse);
      expect(response.asJSONPaging, isNull);
      expect(response.toString(true), contains('body: body'));
      expect(response.toString(), contains('body: 4 bytes'));
      expect(response.memorySize(), greaterThan(4));
      expect(response.instanceDateTime, isA<DateTime>());

      var throwing = HttpResponse(
        HttpMethod.GET,
        'http://a/',
        'http://a/',
        200,
        null,
        responseHeaderGetter: (k) => throw StateError('no headers'),
      );
      expect(throwing.getResponseHeader('x'), isNull);
      expect(throwing.hasBody, isFalse);
      expect(throwing.json, isNull);

      expect(response.compareTo(throwing), lessThanOrEqualTo(0));
      expect(throwing.compareTo(response), greaterThanOrEqualTo(0));
    });

    test(
      'JSON of an error response: HttpError with the requested URL',
      () async {
        var requester = _RecordingRequester()..status = 500;
        var client = HttpClient('http://foo.com/', requester);

        await expectLater(
          client.getJSON('e', parameters: {'a': '1'}),
          throwsA(
            isA<HttpError>()
                .having((e) => e.status, 'status', 500)
                .having((e) => e.url, 'url', 'http://foo.com/e?a=1'),
          ),
        );
      },
    );
  });

  group('HttpRequestBody', () {
    test('body builders', () {
      var builder = HttpRequestBody(
        (Map<String, String?> p) => 'a=${p['a']}',
        'text/plain',
        {'a': 1},
      );
      expect(builder.contentAsString, equals('a=1'));

      var typed = HttpRequestBody(
        (Map<String, String?> p, String? type) => '$type',
        'json',
      );
      expect(typed.contentType, equals('application/json'));
      expect(typed.contentAsString, equals('application/json'));

      var noArgs = HttpRequestBody(() => 'x', null);
      expect(noArgs.contentAsString, equals('x'));

      var other = HttpRequestBody(123, 'text/plain');
      expect(other.contentAsString, equals('123'));
      expect(other.contentAsSendData, equals('123'));

      expect(HttpRequestBody.NULL.isNull, isTrue);
    });
  });

  group('HttpClient', () {
    test('requests through HttpClientRequester.request', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);

      for (var method in HttpMethod.values) {
        var response = await client.request(
          method,
          'r',
          parameters: {'a': '1'},
          body: canHttpMethodHaveBody(method) ? 'b' : null,
          contentType: 'text/plain',
          accept: 'text/plain',
        );
        expect(response.method, equals(method));
        expect(requester.lastRequest!.method, equals(method));
        // `HEAD` and `OPTIONS` have no `accept` (no response body).
        if (method != HttpMethod.HEAD && method != HttpMethod.OPTIONS) {
          expect(requester.lastRequest!.headerAccept, equals('text/plain'));
        }
      }

      var json = await client.requestJSON(HttpMethod.GET, 'j');
      expect(json, isA<Map>());
      expect(await client.optionsJSON('j'), isA<Map>());
      expect(await client.putJSON('j', body: 'x'), isA<Map>());
    });

    test('withBasePath', () {
      var client = HttpClient('http://foo.com:8080/a/');
      expect(
        client.withBasePath('/b').baseURL,
        equals('http://foo.com:8080/b'),
      );
      expect(client.withBaseURL(client.baseURL), same(client));
      expect(client.isBaseUrlLocalhost(), isFalse);
      expect(HttpClient('http://localhost/').isBaseUrlLocalhost(), isTrue);
    });

    test('invalid JSON: FormatException', () async {
      var requester = HttpClientRequesterSimulation()
        ..replyGET(RegExp('.*'), '{invalid');
      var client = HttpClient('http://foo.com/', requester)..logJSON = true;
      await expectLater(client.getJSON('x'), throwsFormatException);
    });

    test('authorization resolution interceptor', () async {
      var requester = _RecordingRequester();
      var client = HttpClient('http://foo.com/', requester);

      Authorization? intercepted;
      client.authorizationResolutionInterceptor = (a) => intercepted = a;

      client.authorization = Authorization.fromProvider(
        (c, e) async => BearerCredential('P'),
      );
      expect(client.isAuthorizationResolved, isFalse);
      expect(client.resolvedAuthorization, isNull);

      await client.get('a');
      expect(intercepted, same(client.authorization));
      expect(client.isAuthorizationResolved, isTrue);
      expect(client.resolvedAuthorization, same(client.authorization));
      expect(
        requester.lastRequest!.requestHeaders!['Authorization'],
        equals('Bearer P'),
      );
    });
  });
}
