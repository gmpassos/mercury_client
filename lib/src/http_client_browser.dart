import 'dart:async';
import 'dart:html' as browser;
import 'dart:typed_data';

import 'package:swiss_knife/swiss_knife.dart';

import 'http_client.dart';

/// HttpClientRequester implementation for Browser.
class HttpClientRequesterBrowser extends HttpClientRequester {
  @override
  Future<HttpResponse> doHttpRequest(HttpClient client, HttpRequest request,
      ProgressListener? progressListener, bool log) {
    if (log) {
      print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
      print(client);
      print(request);
      print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
    }

    var completer = Completer<HttpResponse>();

    var xhr = browser.HttpRequest();

    var methodName = getHttpMethodName(request.method, HttpMethod.GET)!;

    assert(RegExp(r'^(?:GET|OPTIONS|POST|PUT|DELETE|PATCH|HEAD)$')
        .hasMatch(methodName));

    var url = request.requestURL;

    xhr.open(methodName, url, async: true);

    xhr.withCredentials = request.withCredentials;

    if (request.responseType != null) {
      xhr.responseType = request.responseType!;
    }

    if (request.mimeType != null) {
      xhr.overrideMimeType(request.mimeType!);
    }

    if (request.requestHeaders != null) {
      request.requestHeaders!.forEach((header, value) {
        xhr.setRequestHeader(header, value);
      });
    }

    if (progressListener != null) {
      xhr.upload.onProgress.listen((e) {
        try {
          progressListener(request, e.loaded, e.total, _calcLoadRatio(e), true);
        } catch (e, s) {
          print(e);
          print(s);
        }
      });

      xhr.onProgress.listen((e) {
        try {
          progressListener(
              request, e.loaded, e.total, _calcLoadRatio(e), false);
        } catch (e, s) {
          print(e);
          print(s);
        }
      });
    }

    xhr.onLoad.listen((e) {
      if (progressListener != null) {
        try {
          progressListener(
              request, e.loaded, e.total, _calcLoadRatio(e), false);
        } catch (e, s) {
          print(e);
          print(s);
        }
      }

      var status = xhr.status ?? 0;

      var accepted = status >= 200 && status < 300;
      var fileUri = status == 0; // file:// URIs have status of 0.
      var notModified = status == 304;
      // Redirect status is specified up to 307, but others have been used in
      // practice. Notably Google Drive uses 308 Resume Incomplete for
      // resumable uploads, and it's also been used as a redirect. The
      // redirect case will be handled by the browser before it gets to us,
      // so if we see it we should pass it through to the user.
      var unknownRedirect = status > 307 && status < 400;

      if (accepted || fileUri || notModified || unknownRedirect) {
        var response =
            _processResponse(client, request, request.method, request.url, xhr);
        completer.complete(response);
      } else {
        _completeOnError(completer, client, request, progressListener, log,
            status, xhr.responseText, e);
      }
    });

    xhr.onError.listen((e) {
      _completeOnError(completer, client, request, progressListener, log,
          xhr.status ?? 0, xhr.responseText, e);
    });

    if (request.sendData != null) {
      xhr.send(request.sendData);
    } else {
      xhr.send();
    }

    return completer.future;
  }

  double? _calcLoadRatio(browser.ProgressEvent e) =>
      e.loaded == null || e.total == null ? null : e.loaded! / e.total!;

  void _completeOnError(
      Completer<HttpResponse> originalRequestCompleter,
      HttpClient client,
      HttpRequest request,
      ProgressListener? progressListener,
      bool log,
      int status,
      String? responseBody,
      dynamic error) async {
    var message = responseBody ?? _errorToString(error);

    var httpError =
        HttpError(request.url, request.requestURL, status, message, error);

    var requestCompleted = await _checkForRetry(originalRequestCompleter,
        client, request, progressListener, log, status, httpError);

    if (!requestCompleted) {
      var bodyError = error != null ? HttpBody.from(error) : null;
      var response = HttpResponse(
          request.method, request.url, request.requestURL, status, bodyError);
      originalRequestCompleter.complete(response);
    }
  }

  String _errorToString(dynamic error) {
    if (error == null) return '';
    if (error is String) return error;
    if (error is browser.Event) {
      return '{type: ${error.type} ; target: ${error.target} ; error: $error}';
    }
    return '$error';
  }

  Future<bool> _checkForRetry(
      Completer<HttpResponse> originalRequestCompleter,
      HttpClient client,
      HttpRequest request,
      ProgressListener? progressListener,
      bool log,
      int status,
      HttpError httpError) async {
    if (request.retries >= 3) {
      return false;
    }

    if (httpError.isOAuthAuthorizationError) return false;

    if (status == 0 || status == 401) {
      return _checkForRetry_authorizationProvider(originalRequestCompleter,
          client, request, progressListener, log, httpError);
    } else {
      return _checkForRetry_networkIssue(originalRequestCompleter, client,
          request, progressListener, log, status, httpError);
    }
  }

  Future<bool> _checkForRetry_networkIssue(
      Completer<HttpResponse> originalRequestCompleter,
      HttpClient client,
      HttpRequest request,
      ProgressListener? progressListener,
      bool log,
      int status,
      HttpError httpError) async {
    if (status == 0 || status == 504) {
      request.incrementRetries();
      return _retryRequest(
          originalRequestCompleter, client, request, progressListener, log);
    }

    return false;
  }

  Future<bool> _checkForRetry_authorizationProvider(
      Completer<HttpResponse> originalRequestCompleter,
      HttpClient client,
      HttpRequest request,
      ProgressListener? progressListener,
      bool log,
      HttpError httpError) async {
    var authorization = request.authorization;

    if (authorization != null && !authorization.isStaticCredential) {
      var credential = await authorization.resolveCredential(client, httpError);

      if (credential != null) {
        request.incrementRetries();

        var authorization2 = Authorization.fromCredential(credential);
        var request2 = request.copy(client, authorization2);

        return _retryRequest(
            originalRequestCompleter, client, request2, progressListener, log);
      } else {
        var bodyError =
            httpError.error != null ? HttpBody.from(httpError.error) : null;
        var status = httpError.status;
        if (status == 0) status = 401;

        var response = HttpResponse(
            request.method, request.url, request.requestURL, status, bodyError);
        originalRequestCompleter.complete(response);
        return true;
      }
    }

    return false;
  }

  Future<bool> _retryRequest(
      Completer<HttpResponse> originalRequestCompleter,
      HttpClient client,
      HttpRequest request,
      ProgressListener? progressListener,
      bool log) async {
    try {
      if (log) {
        print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
        print('RETRY: ${request.retries}');
        print(request);
        print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>');
      }

      var response =
          await doHttpRequest(client, request, progressListener, log);
      originalRequestCompleter.complete(response);
    } catch (error) {
      originalRequestCompleter.completeError(error);
    }
    return true;
  }

  HttpResponse _processResponse(HttpClient client, HttpRequest request,
      HttpMethod method, String url, browser.HttpRequest xhr) {
    var contentType = xhr.getResponseHeader('Content-Type');
    var status = xhr.status ?? 0;
    var body = xhr.response;
    var irrelevantContent = (status >= 300 && status < 600);

    if (status == 204) {
      body = null;
    }

    var httpBody = HttpBody.from(body, MimeType.parse(contentType));

    if (irrelevantContent &&
        (httpBody!.isString || httpBody.isBytesArray) &&
        httpBody.size == 0) {
      httpBody = HttpBody.from(null, MimeType.parse(contentType));
    }

    var response = HttpResponse(method, url, xhr.responseUrl ?? url, status,
        httpBody, (key) => xhr.getResponseHeader(key), xhr);

    var responseHeaderWithToken = client.responseHeaderWithToken;

    if (responseHeaderWithToken != null) {
      var accessToken = response.getResponseHeader(responseHeaderWithToken);
      if (accessToken != null && accessToken.isNotEmpty) {
        client.authorization =
            Authorization.fromCredential(BearerCredential(accessToken));
      }
    }

    var responseProcessor = client.responseProcessor;

    if (responseProcessor != null) {
      try {
        responseProcessor(client, xhr, response);
      } catch (e) {
        print(e);
      }
    }

    return response;
  }
}

HttpClientRequester createHttpClientRequesterImpl() {
  return HttpClientRequesterBrowser();
}

Uri getHttpClientRuntimeUriImpl() {
  var href = Uri.parse(browser.window.location.href);
  return href;
}

class HttpBlobBrowser extends HttpBlob<browser.Blob> {
  HttpBlobBrowser(browser.Blob blob, MimeType? mimeType)
      : super(blob, mimeType);

  @override
  int size() => blob.size;

  @override
  Future<ByteBuffer> readByteBuffer() {
    var completer = Completer<ByteBuffer>();

    var reader = browser.FileReader();

    reader.onLoadEnd.listen((e) {
      var result = reader.result;

      ByteBuffer? data;
      if (result is ByteBuffer) {
        data = result;
      } else if (result is String) {
        data = Uint16List.fromList(result.codeUnits).buffer;
      } else if (result is List<int>) {
        if (result is TypedData) {
          data = (result as TypedData).buffer;
        } else {
          data = Uint8List.fromList(result).buffer;
        }
      }
      completer.complete(data);
    });

    reader.readAsArrayBuffer(blob);

    return completer.future;
  }
}

HttpBlob? createHttpBlobImpl(Object? content, MimeType? mimeType) {
  if (content == null) return null;
  if (content is HttpBlob) return content;
  if (content is browser.Blob) return HttpBlobBrowser(content, mimeType);
  var blob = browser.Blob([content], mimeType.toString());
  return HttpBlobBrowser(blob, mimeType);
}

bool isHttpBlobImpl(Object? o) => o is HttpBlob || o is browser.Blob;
