@TestOn('vm')

import 'package:test/test.dart';

import 'mercury_client_basic.dart';
import 'test_server.dart';

class VMTestServerChannel implements TestServerChannel {
  @override
  Future<bool> initialize() async {
    return true;
  }

  TestServer? testServer;

  @override
  Future<bool> start() async {
    if (testServer != null && testServer!.isOpen) {
      throw StateError('Previous server still open: $testServer');
    }

    print('[VM] START');

    testServer = TestServer();
    await testServer!.start();
    return true;
  }

  @override
  Future<bool> waitOpen() async {
    print('[VM] WAIT OPEN');

    await testServer!.waitOpen();
    return true;
  }

  @override
  Future<bool> close() async {
    print('[VM] CLOSE');

    await testServer!.close();
    return true;
  }

  @override
  int get serverPort => testServer!.port;
}

void main() {
  doBasicTests(VMTestServerChannel());
}
