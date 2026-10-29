@TestOn('browser')
library;

import 'dart:async';

import 'package:async/async.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import 'mercury_client_basic.dart';

class BrowserTestServerChannel implements TestServerChannel {
  BrowserTestServerChannel();

  StreamChannel? _channel;
  late StreamQueue _channelQueue;

  void setChannel(StreamChannel channel) {
    _channel = channel;
    var stream = _channel!.stream;
    _channelQueue = StreamQueue(stream);
  }

  dynamic _consumeMessage() async {
    print('[BROWSER] CONSUMING...');
    var msg = await _channelQueue.next;
    print('[BROWSER] CONSUMED>>> $msg');
    return msg;
  }

  @override
  Future<bool> initialize() async {
    if (_channel != null) return true;

    var vmCodeUri = 'test_server.dart';

    print('[BROWSER] INITIALIZE>>> spawnHybridUri: $vmCodeUri');

    var channel = spawnHybridUri(vmCodeUri, stayAlive: true);

    setChannel(channel);

    return true;
  }

  void send(String cmd) {
    print('[BROWSER] SEND>>> $cmd');
    _channel!.sink.add(cmd);
  }

  Future<T> receive<T>([T? def]) async {
    var val = (await _consumeMessage()) as T;
    print('[BROWSER] RECEIVE>>> $val');

    if (def != null && val == null) {
      val = def;
    }
    return val;
  }

  @override
  Future<bool> start() async {
    print('[BROWSER] START');

    send('start');
    var ok = await receive(false);
    return ok;
  }

  int? _serverPort;

  @override
  int? get serverPort => _serverPort;

  @override
  Future<bool> waitOpen() async {
    print('[BROWSER] WAIT OPEN');

    send('wait');
    var port = await receive<num>(-1);
    _serverPort = port.toInt();
    return true;
  }

  @override
  Future<bool> close() async {
    print('[BROWSER] CLOSE');

    send('close');
    var ok = await receive(false);
    return ok;
  }
}

void main() {
  var testServerChannel = BrowserTestServerChannel();

  doBasicTests(testServerChannel);

  // Only the browser client retries a request.
  group('HttpClient (browser retries)', () {
    setUp(() async {
      await testServerChannel.initialize();
      await testServerChannel.start();
    });

    tearDown(() async {
      await testServerChannel.close();
    });

    test(
      '401 with an authorization provider: a new credential per retry',
      () async {
        await testServerChannel.waitOpen();

        var lastErrorsStatus = <int?>[];

        var client =
            HttpClient('http://localhost:${testServerChannel.serverPort}/tests')
              ..authorization = Authorization.fromProvider((
                client,
                lastError,
              ) async {
                lastErrorsStatus.add(lastError?.status);
                return BearerCredential('token-${lastErrorsStatus.length}');
              });

        var response = await client.get('foo/401');
        expect(response.status, equals(401));

        // Resolved for the request, then again (with the `401`) for its retry:
        // a new credential, not the rejected one. The retried request has a
        // static copy of it, so a `401` again isn't retried.
        expect(lastErrorsStatus, equals([null, 401]));
      },
    );

    test('401 of concurrent requests: resolved again only once', () async {
      await testServerChannel.waitOpen();

      var lastErrorsStatus = <int?>[];

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests')
            ..authorization = Authorization.fromProvider((
              client,
              lastError,
            ) async {
              lastErrorsStatus.add(lastError?.status);
              await Future.delayed(Duration(milliseconds: 50));
              return BearerCredential('token-${lastErrorsStatus.length}');
            });

      // Resolved before the requests (both sent with the same credential):
      await client.get('foo');
      expect(lastErrorsStatus, equals([null]));

      // The second rejected after the first's credential was resolved again:
      var responses = await Future.wait([
        client.get('foo/401'),
        client.get('foo/401-slow'),
      ]);
      expect(responses.map((r) => r.status), equals([401, 401]));

      // Both rejected, but resolved again only once: the second retry uses
      // the credential already resolved again by the first (not discarding
      // it, resolving a third one).
      expect(lastErrorsStatus, equals([null, 401]));
    });

    test('504: retried (any method)', () async {
      await testServerChannel.waitOpen();

      var client = HttpClient(
        'http://localhost:${testServerChannel.serverPort}/tests',
      );

      // A `504` the first time, then OK: the retry gets the OK.
      var get = await client.get('504-once', parameters: {'id': 'get'});
      expect(get.status, equals(200));

      var post = await client.post(
        '504-once',
        parameters: {'id': 'post'},
        body: 'x',
        contentType: 'text/plain',
      );
      expect(post.status, equals(200));
    });

    test('network error (0): only safe methods are retried', () async {
      // Port 1: refused by the browser (an unsafe port), a status `0`.
      var client = HttpClient('http://localhost:1/');

      var getInit = DateTime.now();
      var getResponse = await client.get('foo');
      var getTime = DateTime.now().difference(getInit);

      expect(getResponse.status, equals(0));
      // 3 retries, after 200, 400 and 600 ms:
      expect(getTime.inMilliseconds, greaterThanOrEqualTo(1200));

      var postInit = DateTime.now();
      var postResponse = await client.post('foo', body: 'x');
      var postTime = DateTime.now().difference(postInit);

      expect(postResponse.status, equals(0));
      // Not retried (it could be applied twice):
      expect(postTime.inMilliseconds, lessThan(1200));
    });
  });
}
