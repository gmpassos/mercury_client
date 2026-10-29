// Benchmarks of `mercury_client`, for the VM and the browser (JS and Wasm).
//
// Run (see `benchmark/README.md`):
//
//   dart test benchmark/mercury_client_benchmark.dart -p vm
//   dart test benchmark/mercury_client_benchmark.dart -p chrome
//   dart test benchmark/mercury_client_benchmark.dart -p chrome -c dart2wasm
//
// Each benchmark prints a Markdown table row: `| name | µs/op | ops/s |`.
// The results are recorded in `benchmark/HISTORY.md`.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:test/test.dart';

const _isWasm = bool.fromEnvironment('dart.tool.dart2wasm');
const _isJS = bool.fromEnvironment('dart.library.js_interop') && !_isWasm;

String get _platform =>
    _isWasm ? 'Chrome (Wasm)' : (_isJS ? 'Chrome (JS)' : 'VM');

/// The warm-up and measured durations of each benchmark.
const _warmup = Duration(milliseconds: 500);
const _measure = Duration(milliseconds: 1500);

/// The results: name -> microseconds per operation.
final _results = <String, double>{};

/// Runs [op] (sync or async) in batches, for [_warmup] and then [_measure],
/// and records the microseconds per operation.
Future<void> _bench(String name, FutureOr<void> Function() op) async {
  Future<(int, int)> run(Duration duration) async {
    var sw = Stopwatch()..start();
    var ops = 0;
    var batch = 1;
    while (sw.elapsedMicroseconds < duration.inMicroseconds) {
      for (var i = 0; i < batch; ++i) {
        var r = op();
        if (r is Future) await r;
      }
      ops += batch;
      if (batch < 1024) batch *= 2;
    }
    sw.stop();
    return (ops, sw.elapsedMicroseconds);
  }

  await run(_warmup);
  var (ops, micros) = await run(_measure);

  var usPerOp = micros / ops;
  _results[name] = usPerOp;

  var opsPerSec = 1000000 / usPerOp;
  print(
    '| $name | ${usPerOp.toStringAsFixed(usPerOp < 10 ? 3 : 1)} '
    '| ${opsPerSec.toStringAsFixed(0)} |',
  );
}

/// A requester answering at once (no network): measures the client.
class _InstantRequester extends HttpClientRequester {
  final HttpBody _body = HttpBody.from('{"ok":true,"n":123}')!;

  @override
  bool setupUserAgent(String? userAgent) => false;

  @override
  Future<HttpResponse> doHttpRequest(
    HttpClient client,
    HttpRequest request,
    ProgressListener? progressListener,
    bool log,
  ) => Future.value(
    HttpResponse(
      request.method,
      request.url,
      request.requestURL,
      200,
      _body,
      responseHeaderGetter: (k) => 'application/json',
      jsonDecoder: client.jsonDecoder,
    ),
  );
}

/// The test server (`test/test_server.dart`), in a VM isolate.
class _Server {
  late final StreamQueue _queue;
  late final StreamSink _sink;

  Future<int> start() async {
    var channel = spawnHybridUri('../test/test_server.dart', stayAlive: true);
    _queue = StreamQueue(channel.stream);
    _sink = channel.sink;
    _sink.add('start');
    await _queue.next;
    _sink.add('wait');
    return ((await _queue.next) as num).toInt();
  }

  Future<void> close() async {
    _sink.add('close');
    await _queue.next;
  }
}

void main() {
  setUpAll(() {
    print('');
    print('## $_platform');
    print('');
    print('| Benchmark | µs/op | ops/s |');
    print('|---|---:|---:|');
  });

  group('client (no network)', () {
    var client = HttpClient('http://localhost:8080/api', _InstantRequester());

    test('GET', () async {
      await _bench('GET with parameters', () async {
        await client.get('users/list', parameters: {'page': '2', 'q': 'x y'});
      });
    }, timeout: Timeout.none);

    test('GET JSON', () async {
      await _bench('GET JSON (getJSON)', () async {
        await client.getJSON('users/1');
      });
    }, timeout: Timeout.none);

    test('POST JSON', () async {
      var body = {
        'name': 'Joe',
        'tags': ['a', 'b', 'c'],
        'n': 123,
      };
      await _bench('POST JSON body', () async {
        await client.post('users', body: body);
      });
    }, timeout: Timeout.none);

    test('POST form', () async {
      await _bench('POST form parameters', () async {
        await client.post('login', parameters: {'user': 'joe', 'pass': '123'});
      });
    }, timeout: Timeout.none);

    test('POST bytes', () async {
      var bytes = Uint8List(16 * 1024);
      await _bench('POST 16KB bytes', () async {
        await client.post(
          'upload',
          body: bytes,
          contentType: 'application/octet-stream',
        );
      });
    }, timeout: Timeout.none);

    test('authorization', () async {
      var authorized =
          HttpClient('http://localhost:8080/api', _InstantRequester())
            ..authorization = Authorization.fromCredential(
              BasicCredential('joe', 'secret'),
            );
      await _bench('GET with Basic authorization', () async {
        await authorized.get('me');
      });
    }, timeout: Timeout.none);
  });

  group('HttpCache', () {
    var client = HttpClient('http://localhost:8080/api', _InstantRequester());

    test('hit', () async {
      var cache = HttpCache();
      var parameters = {'a': '1', 'b': '2'};
      await cache.get(client, 'cached', parameters: parameters);
      await _bench('HttpCache hit', () async {
        await cache.get(client, 'cached', parameters: parameters);
      });
    }, timeout: Timeout.none);

    test('miss', () async {
      var cache = HttpCache(maxCacheMemory: 1024 * 1024);
      var i = 0;
      await _bench('HttpCache miss (memory limit)', () async {
        await cache.get(client, 'item/${i++}');
      });
    }, timeout: Timeout.none);
  });

  group('utilities', () {
    test('buildURLWithQueryParameters', () async {
      var parameters = {'page': '2', 'q': 'a b'};
      await _bench('buildURLWithQueryParameters', () {
        buildURLWithQueryParameters('http://a.com/x/y?z=1', parameters);
      });
    }, timeout: Timeout.none);

    test('status', () async {
      var statuses = [
        for (var s in [0, 200, 204, 301, 400, 401, 404, 429, 451, 500])
          HttpStatus('http://a/', 'http://a/', s),
      ];
      await _bench('HttpStatus.isError (x10)', () {
        for (var s in statuses) {
          s.isError;
        }
      });
    }, timeout: Timeout.none);

    test('headers', () async {
      var request = HttpRequest(
        HttpMethod.POST,
        'http://a/',
        'http://a/',
        requestHeaders: {
          'accept': 'application/json',
          'x-a': '1',
          'x-b': '2',
          'content-type': 'application/json; charset=UTF-8',
        },
      );
      await _bench('HttpRequest header getters (x4)', () {
        request.headerAccept;
        request.headerContentType;
        request.headerContentTypeCharset;
        request.headerContentLength;
      });
    }, timeout: Timeout.none);

    test('HttpBody', () async {
      var text = List.filled(4096, 'açaí ').join();
      var bytes = utf8.encode(text);
      var mimeType = HttpResponse(
        HttpMethod.GET,
        'u',
        'u',
        200,
        null,
        responseHeaderGetter: (k) => 'text/plain; charset=utf-8',
      ).bodyMimeType;
      await _bench('HttpBody bytes asString (24KB UTF-8)', () {
        HttpBody.from(bytes, mimeType)!.asString;
      });

      var view = Uint8List.sublistView(bytes, 1, bytes.length - 1);
      await _bench('HttpBody view asByteBuffer (24KB)', () {
        HttpBody.from(view)!.asByteBuffer;
      });
    }, timeout: Timeout.none);
  });

  group('network (local test server)', () {
    var server = _Server();
    late HttpClient client;

    setUpAll(() async {
      var port = await server.start();
      client = HttpClient('http://localhost:$port/tests');
    });

    tearDownAll(() => server.close());

    test('GET JSON', () async {
      await _bench('network: GET JSON (echo)', () async {
        await client.getJSON('echo', parameters: {'a': '1'});
      });
    }, timeout: Timeout.none);

    test('download', () async {
      await _bench('network: GET 1MB bytes', () async {
        var r = await client.get('bytes', parameters: {'size': '1048576'});
        if (r.bodyLength != 1048576) throw StateError('size: ${r.bodyLength}');
      });
    }, timeout: Timeout.none);

    test('text', () async {
      await _bench('network: GET 256KB UTF-8 text (bodyAsString)', () async {
        var r = await client.get('text', parameters: {'size': '262144'});
        if (r.bodyAsString!.length != 262144) {
          throw StateError('length: ${r.bodyAsString!.length}');
        }
      });
    }, timeout: Timeout.none);

    test('upload', () async {
      var bytes = Uint8List(256 * 1024);
      await _bench('network: POST 256KB bytes (echoed)', () async {
        var r = await client.post(
          'bytes',
          body: bytes,
          contentType: 'application/octet-stream',
        );
        if (r.bodyLength != bytes.length) {
          throw StateError('size: ${r.bodyLength}');
        }
      });
    }, timeout: Timeout.none);
  });
}
