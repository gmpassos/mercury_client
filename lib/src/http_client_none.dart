import 'dart:async';

import 'http_client.dart';

class HttpClientRequesterNone extends HttpClientRequester {

  @override
  Future<HttpResponse> doHttpRequest(HttpClient client, HttpRequest request) {
    return Future.error( HttpError( request.requestURL, 0, 'No HttpClientRequester for ${ request.method } request: ${ request.requestURL }', null) ) ;
  }

}


HttpClientRequester createHttpClientRequester() {
  return HttpClientRequesterNone() ;
}

