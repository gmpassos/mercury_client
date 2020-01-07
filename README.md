# Mercury Client

A Simple Dart HTTP client with Web and Native support.

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

## Mercury (mythology)

Mercury is known to the Romans as Mercurius.

He is the god of financial gain, commerce, eloquence, messages, communication (including divination), travelers, boundaries, luck, trickery and thieves.

- See: [Mercury@Wikipedia](https://en.wikipedia.org/wiki/Mercury_(mythology)

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/gmpassos/mercury_client/issues

## Author

Graciliano M. Passos: [gmpassos@GitHub][github].

[github]: https://github.com/gmpassos

## License

Dart free & open-source [license](https://github.com/dart-lang/stagehand/blob/master/LICENSE).
