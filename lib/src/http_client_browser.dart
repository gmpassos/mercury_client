import 'dart:async';
import 'dart:html' as browser;
import 'dart:html';

import 'http_client.dart';

/// HttpClientRequester implementation for Browser.
class HttpClientRequesterBrowser extends HttpClientRequester {
  @override
  Future<HttpResponse> doHttpRequest(
      HttpClient client, HttpRequest request, bool log) {

    if (log) {
      print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      print(client);
      print(request);
      print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
    }

    var completer = Completer<HttpResponse>();

    var xhr = browser.HttpRequest();

    var methodName = getHttpMethodName(request.method, HttpMethod.GET) ;

    assert( RegExp(r'^(?:GET|OPTIONS|POST|PUT|DELETE|PATCH|HEAD)$').hasMatch(methodName) ) ;

    var url = request.requestURL;

    xhr.open(methodName , url, async: true);

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
        var response =
            _processResponse(client, request.method, request.url, xhr);
        completer.complete(response);
      } else {
        _completeOnError(
            completer, client, request, log, xhr.status, xhr.responseText, e);
      }
    });

    xhr.onError.listen((e) {
      _completeOnError(
          completer, client, request, log, xhr.status, xhr.responseText, e);
    });

    if (request.sendData != null) {
      xhr.send(request.sendData);
    } else {
      xhr.send();
    }

    return completer.future;
  }

  void _completeOnError(
      Completer<HttpResponse> originalRequestCompleter,
      HttpClient client,
      HttpRequest request,
      bool log,
      int status,
      String responseBody,
      dynamic error) async {
    var message = responseBody ?? '$error';

    var httpError =
        HttpError(request.url, request.requestURL, status, message, error);

    var requestCompleted = await _checkForRetry(
        originalRequestCompleter, client, request, log, status, httpError);

    if (!requestCompleted) {
      originalRequestCompleter.completeError(httpError);
    }
  }

  Future<bool> _checkForRetry(
      Completer<HttpResponse> originalRequestCompleter,
      HttpClient client,
      HttpRequest request,
      bool log,
      int status,
      HttpError httpError) async {
    if (request.retries >= 3) {
      return false;
    }

    if (httpError.isOAuthAuthorizationError) return false;

    if (status == 0 || status == 401) {
      return _checkForRetry_authorizationProvider(
          originalRequestCompleter, client, request, log, httpError);
    } else {
      return _checkForRetry_networkIssue(
          originalRequestCompleter, client, request, log, status, httpError);
    }
  }

  Future<bool> _checkForRetry_networkIssue(
      Completer<HttpResponse> originalRequestCompleter,
      HttpClient client,
      HttpRequest request,
      bool log,
      int status,
      HttpError httpError) async {
    if (status == 0 || status == 504) {
      request.incrementRetries();
      return _retryRequest(originalRequestCompleter, client, request, log);
    }

    return false;
  }

  Future<bool> _checkForRetry_authorizationProvider(
      Completer<HttpResponse> originalRequestCompleter,
      HttpClient client,
      HttpRequest request,
      bool log,
      HttpError httpError) async {
    if (request.authorization != null &&
        request.authorization.authorizationProvider != null) {
      var authorizationProvider = request.authorization.authorizationProvider;
      var credential = await authorizationProvider(client, httpError);

      if (credential != null) {
        request.incrementRetries();

        var authorization2 = Authorization(credential);
        var request2 = request.copy(client, authorization2);

        return _retryRequest(originalRequestCompleter, client, request2, log);
      } else {
        originalRequestCompleter.completeError(httpError);
        return true;
      }
    }

    return false;
  }

  Future<bool> _retryRequest(Completer<HttpResponse> originalRequestCompleter,
      HttpClient client, HttpRequest request, bool log) async {
    try {
      if (log) {
        print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
        print('RETRY: ${request.retries}');
        print(request);
        print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
      }

      var response = await doHttpRequest(client, request, log);
      originalRequestCompleter.complete(response);
    } catch (error) {
      originalRequestCompleter.completeError(error);
    }
    return true;
  }

  //////////////////////////////////

  HttpResponse _processResponse(
      HttpClient client, HttpMethod method, String url, browser.HttpRequest xhr) {
    var resp = HttpResponse(method, url, xhr.responseUrl, xhr.status,
        xhr.responseText, (key) => xhr.getResponseHeader(key), xhr);

    var responseHeaderWithToken = client.responseHeaderWithToken;

    if (responseHeaderWithToken != null) {
      var accessToken = resp.getResponseHeader(responseHeaderWithToken);
      if (accessToken != null) {
        client.authorization = BearerCredential(accessToken);
      }
    }

    var responseProcessor = client.responseProcessor;

    if (responseProcessor != null) {
      try {
        responseProcessor(client, xhr, resp);
      } catch (e) {
        print(e);
      }
    }

    return resp;
  }
}

HttpClientRequester createHttpClientRequesterImpl() {
  return HttpClientRequesterBrowser();
}

Uri getHttpClientRuntimeUriImpl() {
  var href = Uri.parse(window.location.href);
  return href;
}
