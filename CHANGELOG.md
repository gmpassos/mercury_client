## 2.3.0

- Change use of `dart:html` to package `web`.

- `HttpRequest`:
  - `sendData`: return `Object?` (instead of `dynamic`).

- swiss_knife: ^3.3.0
- web: ^1.1.0
- js_interop_utils: ^1.0.6

## 2.2.5

- `HttpClient`:
  - `requestJSON`, `getJSON`, `optionsJSON`, `postJSON`, `putJSON`:
    - Call `_jsonDecodeResponse` to handle response errors, and avoid direct call to `_jsonDecode`.
  - `_jsonDecodeResponse`: throw an `HttpError` on error status responses.

- New `WithHttpStatus`.

- `HttpError`: now extends `Error` with `WithHttpStatus`.
  - Added field `httpStatus`.

- swiss_knife: ^3.2.3
- collection: ^1.19.0

- lints: ^5.1.1
- test: ^1.25.15
- stream_channel: ^2.1.4
- async: ^2.13.0
- coverage: ^1.11.1

## 2.2.4

- `HttpBody`:
  - Optimize internal resolution of: `size`, `asString`, `asByteBuffer`, `asByteArray`.

## 2.2.3

- `HttpBody`:
  - Added `bytesToString`, to correctly convert `body` bytes using `mimeType` to determine the `Encoding`. 

- `BasicCredential.base64`:
  - Use `utf8` to decode.

- `browser.HttpRequest()`:
  - `responseType = 'arraybuffer'`

- `HttpClient`:
  - Pass parameter `responseType` to the requests.

- sdk: '>=3.3.0 <4.0.0'

- swiss_knife: ^3.2.2
- charset: ^2.0.1
- test: ^1.25.8
- coverage: ^1.9.2

## 2.2.2

- `HttpResponse`:
  - Added field `error`.

- `HttpClientRequesterBrowser`: better error handling and body/message parsing for HTTP errors. 

- swiss_knife: ^3.2.0
- test: ^1.25.2

## 2.2.1

- lints: ^3.0.0
  - Fix lints.
- swiss_knife: ^3.1.6
- coverage: ^1.7.2
- dependency_validator: ^3.2.3

## 2.2.0

- `HttpStatus`: added `isStatusRedirect`.
- `HttpResponse`: added `redirects` and `redirectToLocation`.
- Dart CI: update and optimize jobs.

- sdk: '>=3.0.0 <4.0.0'

- swiss_knife: ^3.1.5
- collection: ^1.18.0
- lints: ^2.1.1
- test: ^1.24.6
- stream_channel: ^2.1.2
- async: ^2.11.0
- coverage: ^1.6.3

## 2.1.8

- swiss_knife: ^3.1.3
- test: ^1.22.1

## 2.1.7

- `HttpClient`:
  - Added `userAgent`.
- `HttpClientRequester`: 
  - Added `setupUserAgent`.
- `HttpClientRequesterIO`:
  - `req.headers.add` with `preserveHeaderCase`:
    Some servers (like IPP printers) won't accept lower-case headers. 
- `HttpRequest`:
  - `updateContentLength`: won't set `Content-Length` if `Transfer-Encoding: chunked` is defined.
  - `sendDataAsString`: tries to decode using UTF-8 and if fails uses LATIN1.
- sdk: '>=2.18.0 <3.0.0'
- collection: ^1.17.0
- lints: ^2.0.1
- stream_channel: ^2.1.1
- async: ^2.10.0 
- dependency_validator: ^3.2.2
- coverage: ^1.6.1

## 2.1.6

- Browser implementation:
  - Ignore forbidden headers for a request.

## 2.1.5

- Improve GitHub CI.
- swiss_knife: ^3.1.1

## 2.1.4

- Added `HttpClient.jsonDecoder`.

## 2.1.3

- Fix upload of raw bytes (`Uint8List`).

## 2.1.2

- Improve `HttpRequest` handling of body headers:
  - `Content-Type` (`Mime-Type` and `charset`)
  - `sendData` (request body) as bytes.
  - `Content-Length` from `sendData`.
- Improve request logging.
- `HttpClient` request `parameters` values now can be a `Object?`.

## 2.1.1

- `parameters` now accepts `Map<String,String?>`.
- Using Dart coverage for `VM` and `Browser` tests.
- Improved tests.
- Migrated from `pedantic` to `lints`.
- lints: ^1.0.1
- swiss_knife: ^3.0.8
- dependency_validator: ^3.1.0

## 2.1.0

- Added `HttpClientInterceptor`.
- Added missing `HttpClient.requestHEAD` implementation.
- `HttpCache`: added `onStaleResponse` and `staleResponseDelay`, to allow
  use of already cached response while requesting a new response.

## 2.0.3

- Add `header` parameter to request methods.
- `HttpCache`: fix `parameter` issue to identify already cached request.
- swiss_knife: ^3.0.7

## 2.0.2

- Null Safety adjustments.

## 2.0.1

- Sound null safety compatibility.
- enum_to_string: ^2.0.1
- swiss_knife: ^3.0.6
  
## 2.0.0-nullsafety.3

- Null safety adjustments.
- swiss_knife: ^3.0.5. 

## 2.0.0-nullsafety.2

- Null Safety adjustments.
- swiss_knife: ^3.0.2
  
## 2.0.0-nullsafety.1

- Dart 2.12.0:
  - Sound null safety compatibility.
  - Update CI dart commands.
  - sdk: '>=2.12.0 <3.0.0'
- enum_to_string: ^2.0.0-nullsafety.1
- swiss_knife: ^3.0.1
- collection: ^1.15.0-nullsafety.4
  
## 1.1.19

- Better handling of body for responses of status from 400 to 599.
- Fix `_jsonDecode`: better handling of null json. 
- Dart 2.12.0+ compliant: `dartfmt` and `dartanalyzer`.
- swiss_knife: ^2.5.26

## 1.1.18

- Added `browser` test.
  - Tests now runs with `vm` and `browser` platform.
  - The browser test uses `spawnHybridUri`, to run at the same time the `TestServer` in VM.
  - The VM test run normally, running `TestServer` in the same VM of tests.
- `.github/workflows`: Now supports tests in FireFox. 
- Added dev_dependencies:
  - stream_channel: ^2.0.0
  - async: ^2.4.2

## 1.1.17

- Added parameter `queryString`.
- Added `ProgressListener`.

## 1.1.16

- `HttpRequest` and `HttpClient`: Added `noQueryString` parameter.

## 1.1.15

- `HttpClient`:
  - `baseURL` now is normalized with `trimLeft()`, since any URI can't start with spaces.
  - Added `withBasePath` and `withBaseURL`.
  - `PUT`, `PATH` and `DELETE` now accepts `queryParameters`.
- `Authorization`: credential resolution handles better exceptions when calling [authorizationProvider].
- `HttpBody`: Added `isMap` and `asMap`.
- swiss_knife: ^2.5.20

## 1.1.14

- Renamed `HttpBody` to `HttpRequestBody`.
- New class `HttpBody`, to wrap multiple types of data body.
- `HttpResponse.body` now is a `HttpBody` no a `String`.
- enum_to_string: ^1.0.14
- swiss_knife: ^2.5.19
  
## 1.1.13

- Using `encodeJSON` that accepts more dynamic trees.
- Avoid empty querystring at the end of path (`.../foo?`) for empty `queryParameters`. 
- enum_to_string: ^1.0.13
- swiss_knife: ^2.5.16

## 1.1.12

- `buildURLWithQueryParameters`:
  - avoid empty fragment in URL.
  - new parameter `removeFragment` to force null URL fragment. 
- swiss_knife: ^2.5.13

## 1.1.11

- swiss_knife: ^2.5.12
- pedantic: ^1.9.2
- test: ^1.15.3
- test_coverage: ^0.4.3

## 1.1.10

- Added `HttpResponse.bodyMimeType`.
- Change parameter name `queryParameters` to `parameters`.
- Request `parameters` now accepts variables in values: `{{var}}`.
- dartfmt.
- swiss_knife: ^2.5.10
- CI: dartanalyzer

## 1.1.9

- `HttpBody: can be generated by a `Function` that can receive `parameters`.
- `HttpCall`: Defines and performs HTTP calls.
- swiss_knife: ^2.5.5

## 1.1.8

- Refactor class Authorization: _AuthorizationStatic, _AuthorizationResolvable.
- Change field HttpClient.authorization from Credential to Authorization.
- Added HttpClient.authorizationResolutionInterceptor
- swiss_knife: ^2.5.3

## 1.1.7

- Fix HTTPS request for dart:io implementation.
- Reuse connections for dart:io implementation.
- Added example.
- Fix documentation.
- dartfmt.

## 1.1.6

- Implementation of DELETE HTTP Method.
- Added HttpClient.urlFilter: HttpClientURLFilter
- Internally use of `HttpMethod` enum when possible. Avoids use of Method as String.
- API Documentation.
- dartfmt and clean code.
- swiss_knife: ^2.4.1

## 1.1.5

- getHttpClientRuntimeUri()
- HttpRequester integrated with JSONPaging.
- HttpResponse.asJSONPaging

## 1.1.4

- HttpResponse.bodyType/isBodyTypeJSON
- BearerCredential.findToken
- fix HttpResponse.getResponseHeader()
- getHttpMethod()
- swiss_knife: ^2.3.9

## 1.1.3

- swiss_knife: ^2.3.7

## 1.1.2

- Fix HttpCache to identify requests with complex body already in cache.
- HttpError: response body as HttpError.message.
- swiss_knife: ^2.3.4

## 1.1.1

- swiss_knife: ^2.3.1

## 1.1.0

- Fix parsing of Uri path with encoded char (ex.: %20).
- Fix automatic set of application/x-www-form-urlencoded when sending POST query parameters.
- Retry request with network error.
- Fix HttpCache requests with dynamic body.
- swiss_knife: ^2.3.0

## 1.0.9

- BearerCredential.fromJSONToken

## 1.0.8

- HttpClient: fullPath parameter to indicate that the path is full (from root).
- HttpClient._buildRequestAuthorization: fix case when result is a null credential.

## 1.0.7

- JSONBodyCredential: creates a JSON body with authentication for each request.
- HttpBody: now a request body is dynamic, it can be Map and List (automatically converted to JSON) or a normal String.

## 1.0.6

- Public method buildRequestURL.
- HttpCache class: handles requests cache with entries timeout and memory limit.


## 1.0.5

- Update dependencies.
- Code analysis.

## 1.0.4

- Update dependencies.
- Code analysis.

## 1.0.3

- Add Author and License to README.

## 1.0.1

- Code analysis

## 1.0.0

- Initial version, created by Stagehand
