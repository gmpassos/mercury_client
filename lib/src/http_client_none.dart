import 'dart:async';

import 'http_client.dart';

class HttpClientRequesterNone extends HttpClientRequester {
  @override
  Future<HttpResponse> doHttpRequest(
      HttpClient client, HttpRequest request, bool log) {
    return Future.error(HttpError(
        request.url,
        request.requestURL,
        0,
        'No HttpClientRequester for ${request.method} request: ${request.requestURL}',
        null));
  }
}

HttpClientRequester createHttpClientRequesterImpl() {
  return HttpClientRequesterNone();
}

Uri getHttpClientRuntimeUriImpl() {
  return Uri(scheme: 'http', host: 'localhost', port: 80);
}
