import 'dart:async';
import 'dart:html' as browser ;

import 'http_client.dart';

class HttpClientRequesterBrowser extends HttpClientRequester {

  @override
  Future<HttpResponse> doHttpRequest( HttpClient client, HttpRequest request ) {
    var completer = Completer<HttpResponse>();

    var xhr = browser.HttpRequest();

    var method = request.method ?? 'GET' ;

    var url = request.requestURL ;

    xhr.open(method, url, async: true);

    if (request.withCredentials != null) {
      xhr.withCredentials = request.withCredentials;
    }

    if (request.responseType != null) {
      xhr.responseType = request.responseType;
    }

    if (request.mimeType != null) {
      xhr.overrideMimeType(request.mimeType);
    }

    if (request.requestHeaders != null) {
      request.requestHeaders.forEach((header, value) {
        xhr.setRequestHeader(header, value);
      });
    }

    xhr.onLoad.listen((e) {
      var accepted = xhr.status >= 200 && xhr.status < 300;
      var fileUri = xhr.status == 0; // file:// URIs have status of 0.
      var notModified = xhr.status == 304;
      // Redirect status is specified up to 307, but others have been used in
      // practice. Notably Google Drive uses 308 Resume Incomplete for
      // resumable uploads, and it's also been used as a redirect. The
      // redirect case will be handled by the browser before it gets to us,
      // so if we see it we should pass it through to the user.
      var unknownRedirect = xhr.status > 307 && xhr.status < 400;

      if (accepted || fileUri || notModified || unknownRedirect) {
        var response = _processResponse(client, request.method, request.url, xhr) ;
        completer.complete(response);
      }
      else {
        _completeOnError(completer, client, request, xhr.status, e) ;
      }
    });

    xhr.onError.listen( (e) {
      _completeOnError(completer, client, request, xhr.status, e) ;
    } );

    if (request.sendData != null) {
      xhr.send(request.sendData);
    } else {
      xhr.send();
    }

    return completer.future ;
  }

  void _completeOnError(Completer<HttpResponse> completer, HttpClient client, HttpRequest request, int status, dynamic error) {
    var restError = HttpError(request.url, request.requestURL, status, '$error', error);

    if ( ( status == 0 || status == 401 ) && request.authorization != null && request.authorization.authorizationProvider != null ) {
      var authorizationProvider = request.authorization.authorizationProvider ;
      var futureCredential = authorizationProvider( client , restError ) ;

      if (futureCredential != null) {
        futureCredential.then( (c) {
          if (c != null) {
            var authorization2 = Authorization(c);
            var request2 = request.copy(client, authorization2) ;

            var futureResponse2 = doHttpRequest(client, request2) ;

            futureResponse2.then( (response2) {
              completer.complete(response2) ;
            }).catchError( (error2) {
              completer.completeError(error2) ;
            } ) ;
          }
          else {
            completer.completeError( restError );
          }
        }).catchError( (e) {
          completer.completeError( restError );
        } ) ;

        return ;
      }
    }

    completer.completeError( restError );
  }

  HttpResponse _processResponse(HttpClient client, String method, String url, browser.HttpRequest xhr) {
    var resp = HttpResponse(method, url, xhr.responseUrl, xhr.status, xhr.responseText, (key) => xhr.getResponseHeader(key), xhr) ;

    var responseHeaderWithToken = client.responseHeaderWithToken ;

    if (responseHeaderWithToken != null) {
      var accessToken = resp.getResponseHeader(responseHeaderWithToken) ;
      if (accessToken != null) {
        client.authorization = BearerCredential(accessToken) ;
      }
    }

    var responseProcessor = client.responseProcessor ;

    if (responseProcessor != null) {
      try {
        responseProcessor(client, xhr, resp);
      }
      catch (e) {
        print(e) ;
      }
    }

    return resp ;
  }


}


HttpClientRequester createHttpClientRequester() {
  return HttpClientRequesterBrowser() ;
}



