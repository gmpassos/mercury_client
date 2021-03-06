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

      expect(response.isOK, equals(true));
      expect(response.isNotOK, equals(false));
      expect(response.isError, equals(false));

      expect(response.bodyAsString,
          equals('Hello, world! Method: GET ; Path: /tests/foo?a=123'));

      print('PROGRESS: $progress');

      expect(
          progress.firstWhereOrNull(
                  (e) => e.contains('download[') && e.contains('/50]')) !=
              null,
          isTrue);
    });

    test('Method GET - 404', () async {
      await testServerChannel.waitOpen();

      var client =
          HttpClient('http://localhost:${testServerChannel.serverPort}/tests');
      expect(client.baseURL, matches(RegExp(r'http://localhost:\d+/tests')));

      var response = await client.get('foo/404');

      expect(response.isOK, equals(false));
      expect(response.isNotOK, equals(true));
      expect(response.isError, equals(false));
      expect(response.status, equals(404));

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

      expect(response.isOK, equals(false));
      expect(response.isNotOK, equals(true));
      expect(response.isError, equals(true));
      expect(response.status, equals(500));

      expect(response.bodyAsString, isNull);

      var responseJSON = await client.getJSON('foo/500');
      expect(responseJSON, isNull);
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

      expect(response.isOK, equals(true));

      expect(
          response.bodyAsString,
          equals(
              'Hello, world! Method: POST ; Path: /tests/foo?%C3%A1=12+3&b=456 ; Content-Type: application/json <Boooodyyy!>'));
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

      expect(response.isOK, equals(true));

      expect(
          response.bodyAsString,
          equals(
              'Hello, world! Method: POST ; Path: /tests/foo/1001?%C3%A1=12+3&b=456&id=1001 ; Content-Type: application/json <Body!>'));
    });
  });
}
