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
