@TestOn('browser')
library;

import 'dart:async';

import 'package:async/async.dart';
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
  doBasicTests(BrowserTestServerChannel());
}
