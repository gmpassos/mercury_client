# Mercury_Client

[![pub package](https://img.shields.io/pub/v/mercury_client.svg?logo=dart&logoColor=00b9fc)](https://pub.dartlang.org/packages/mercury_client)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)
[![Dart CI](https://github.com/gmpassos/mercury_client/actions/workflows/dart.yml/badge.svg?branch=master)](https://github.com/gmpassos/mercury_client/actions/workflows/dart.yml)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/mercury_client?logo=git&logoColor=white)](https://github.com/gmpassos/mercury_client/releases)
[![New Commits](https://img.shields.io/github/commits-since/gmpassos/mercury_client/latest?logo=git&logoColor=white)](https://github.com/gmpassos/mercury_client/network)
[![Last Commits](https://img.shields.io/github/last-commit/gmpassos/mercury_client?logo=git&logoColor=white)](https://github.com/gmpassos/mercury_client/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/gmpassos/mercury_client?logo=github&logoColor=white)](https://github.com/gmpassos/mercury_client/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/gmpassos/mercury_client?logo=github&logoColor=white)](https://github.com/gmpassos/mercury_client)
[![License](https://img.shields.io/github/license/gmpassos/mercury_client?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/mercury_client/blob/master/LICENSE)

Portable HTTP client (Browser and Native support) with memory cache. 

## Methods:

  - GET
  - HEAD
  - POST
  - PUT
  - DELETE
  - PATCH
  - OPTIONS.

## Usage

A simple usage example:

```dart
import 'package:mercury_client/mercury_client.dart';

main() async {
  
  var client = HttpClient('http://gateway.your.domain/api-1');

  try {
    // Request with POST method:
    // URL: http://gateway.your.domain/api-1/call-foo?var=123
    // Content-Type: application/json
    // Body: { 'content': 'any' }
    var response = await client.post(
      'call-foo',
      parameters: {'var': '123'},
      body: "{ 'content': 'any' }",
      contentType: 'application/json',
    );

    if (response.isOK) {
      print(response.body);
    }
  } catch (e) {
    print('Error requesting URL: $e');
  }
  
}
```

### HttpCache Usage

Using `HttpCache` you can perform in-memory cached requests.

You can pass the parameter `onStaleResponse` for the notification of a stale version
(a cached response that can be used while a new request is being performed):

```dart
import 'package:mercury_client/mercury_client.dart';

main() async {

  // HTTP Cache with max memory of 16M and timeout of 5min:
  var cache = HttpCache(
          maxCacheMemory: 1024 * 1024 * 16, timeout: Duration(minutes: 5));

  // The image element that will received the loaded data:
  var img = ImageElement();

  try {
    // Request an image URL, that can be cached.
    // If a stale version (already cached instance with timeout) exits,
    // `onStaleResponse` will be called to indicate the existence
    // of a cached response to be used while requesting the URL.
    var response = await cache.getURL(
      'http://host/path/to/base64/image.jpeg',
      onStaleResponse: (staleResponse) {
        var staleTime = staleResponse.instanceDateTime;
        print('Stale image available: $staleTime');
        img.src = 'data:image/jpeg;base64,${staleResponse.bodyAsString}';
      },
    );

    if (response.isOK) {
      img.src = 'data:image/jpeg;base64,${response.bodyAsString}';
    }
  } catch (e) {
    print('Error requesting URL: $e');
  }

}
```

## Mercury (mythology)

Mercury is known to the Romans as Mercurius.

He is the god of financial gain, commerce, eloquence, **messages, communication** (including divination), travelers, boundaries, luck, trickery and thieves.

- See: [Mercury@Wikipedia](https://en.wikipedia.org/wiki/Mercury_(mythology))

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

## Source

The official source code is [hosted @ GitHub][github_mercury_client]:

- https://github.com/gmpassos/mercury_client

[github_mercury_client]: https://github.com/gmpassos/mercury_client

# Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

# Contribution

Any help from the open-source community is always welcome and needed:
- Found an issue?
    - Please [fill a bug report][tracker] with details.
- Wish a feature?
    - Open a feature request with use cases.
- Are you using and liking the project?
    - Promote the project: create an article, do a post or make a donation.
- Are you a developer?
    - Fix a bug and send a [pull request][pull_request].
    - Implement a new feature.
    - Improve the Unit Tests.
- Have you already helped in any way?
    - **Many thanks from me, the contributors and everybody that uses this project!**


[tracker]: https://github.com/gmpassos/mercury_client/issues
[pull_request]: https://github.com/gmpassos/mercury_client/pulls

## Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

Dart free & open-source [license](https://github.com/dart-lang/stagehand/blob/master/LICENSE).
