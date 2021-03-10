# Mercury_Client

[![pub package](https://img.shields.io/pub/v/mercury_client.svg?logo=dart&logoColor=00b9fc)](https://pub.dartlang.org/packages/mercury_client)
[![Null Safety](https://img.shields.io/badge/null-safety-brightgreen)](https://dart.dev/null-safety)

[![CI](https://img.shields.io/github/workflow/status/gmpassos/mercury_client/Dart%20CI/master?logo=github-actions&logoColor=white)](https://github.com/gmpassos/mercury_client/actions)
[![GitHub Tag](https://img.shields.io/github/v/tag/gmpassos/mercury_client?logo=git&logoColor=white)](https://github.com/gmpassos/mercury_client/releases)
[![New Commits](https://img.shields.io/github/commits-since/gmpassos/mercury_client/latest?logo=git&logoColor=white)](https://github.com/gmpassos/mercury_client/network)
[![Last Commits](https://img.shields.io/github/last-commit/gmpassos/mercury_client?logo=git&logoColor=white)](https://github.com/gmpassos/mercury_client/commits/master)
[![Pull Requests](https://img.shields.io/github/issues-pr/gmpassos/mercury_client?logo=github&logoColor=white)](https://github.com/gmpassos/mercury_client/pulls)
[![Code size](https://img.shields.io/github/languages/code-size/gmpassos/mercury_client?logo=github&logoColor=white)](https://github.com/gmpassos/mercury_client)
[![License](https://img.shields.io/github/license/gmpassos/mercury_client?logo=open-source-initiative&logoColor=green)](https://github.com/gmpassos/mercury_client/blob/master/LICENSE)

Portable HTTP client (Browser and Native support) with memory cache. 

## Methods:

  - GET
  - POST
  - PUT
  - DELETE
  - PATCH
  - OPTIONS.

## Usage

A simple usage example:

```dart
import 'package:mercury_client/mercury_client.dart';
import 'dart:async';

main() async {
  
  var client = HttpClient('http://gateway.your.domain/api-1') ;

  // Calling with POST method:
  // URL: http://gateway.your.domain/api-1/call-foo?var=123
  // Content-Type: application/json
  // Body:
  // { 'content': 'any' }}
  var response = await client.post("call-foo", parameters: {'var': '123'}, body: "{ 'content': 'any' }}", contentType: 'application/json') ;
  
  if ( response.isOK ) {
    print( response.body ) ;
  }

}
```

HttpCache usage:


```dart
import 'package:mercury_client/mercury_client.dart';
import 'dart:async';

main() async {
  
  var client = HttpClient('http://gateway.your.domain/api-1') ;
  
  // HTTP Cache with max memory of 16M and timeout of 5min:
  var cache = HttpCache(1024*1024*16, 1000*60*5) ;

  var response = cache.getURL( 'http://host/path/to/base64/image.jpeg') ;

  if ( response.isOK ) {
    img.src = 'data:image/jpeg;base64,'+ response.body ;
  }

}
```

## Mercury (mythology)

Mercury is known to the Romans as Mercurius.

He is the god of financial gain, commerce, eloquence, **messages, communication** (including divination), travelers, boundaries, luck, trickery and thieves.

- See: [Mercury@Wikipedia](https://en.wikipedia.org/wiki/Mercury_(mythology)

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/gmpassos/mercury_client/issues

## Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

Dart free & open-source [license](https://github.com/dart-lang/stagehand/blob/master/LICENSE).
