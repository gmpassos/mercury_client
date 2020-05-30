import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'http_client.dart';

/// HttpClientRequester implementation for VM [dart:io].
class HttpClientRequesterIO extends HttpClientRequester {
  @override
  Future<HttpResponse> doHttpRequest(
      HttpClient client, HttpRequest request, bool log) async {
    var uri = Uri.parse(request.requestURL);

    var req = await _request(client, request, uri);

    var r = await req.close();

    return _processResponse(client, request.method, request.url, uri, r);
  }

  Future<HttpResponse> _processResponse(HttpClient client, HttpMethod method,
      String url, Uri requestURI, io.HttpClientResponse r) async {
    var contentType = r.headers.contentType;
    var body = await _decodeBody(contentType, r);

    var responseHeaders = await _decodeHeaders(r);

    var resp = HttpResponse(method, url, requestURI.toString(), r.statusCode,
        body, (key) => responseHeaders[key.toLowerCase()], r);

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
        responseProcessor(client, r, resp);
      } catch (e) {
        print(e);
      }
    }

    return resp;
  }

  ////////////////////////////////

  Future<String> _decodeBody(
      io.ContentType contentType, io.HttpClientResponse r) async {
    var decoder = contentType != null
        ? contentTypeToDecoder(contentType.mimeType, contentType.charset)
        : latin1.decoder;
    return decoder.bind(r).join();
  }

  Future<Map<String, String>> _decodeHeaders(io.HttpClientResponse r) async {
    // ignore: omit_local_variable_types
    Map<String, String> headers = {};

    r.headers.forEach((key, vals) {
      headers[key] = vals != null && vals.isNotEmpty ? vals[0] : null;
    });

    return headers;
  }

  ////////////////////////////////

  Future<io.HttpClientRequest> _request(
      HttpClient client, HttpRequest request, Uri uri) async {
    var method = request.method;

    method ??= HttpMethod.GET;

    switch (method) {
      case HttpMethod.GET:
        return _requestGET(client, request, uri);
      case HttpMethod.POST:
        return _requestPOST(client, request, uri);
      case HttpMethod.PUT:
        return _requestPUT(client, request, uri);
      case HttpMethod.PATCH:
        return _requestPATCH(client, request, uri);
      case HttpMethod.DELETE:
        return _requestDELETE(client, request, uri);
      case HttpMethod.HEAD:
        return _requestHEAD(client, request, uri);
      default:
        throw UnsupportedError("Can't handle method: $method");
    }
  }

  Future<io.HttpClientRequest> _requestGET(
      HttpClient client, HttpRequest request, Uri uri) async {
    var req = await io.HttpClient()
        .get(uri.host, uri.port, toPathWithQuery(uri, request));
    _putRequestHeaders(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestPOST(
      HttpClient client, HttpRequest request, Uri uri) async {
    var req = await io.HttpClient()
        .post(uri.host, uri.port, toPathWithQuery(uri, request));
    _putRequestHeaders(request, req);
    _putSendData(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestPUT(
      HttpClient client, HttpRequest request, Uri uri) async {
    var req = await io.HttpClient()
        .put(uri.host, uri.port, toPathWithQuery(uri, request));
    _putRequestHeaders(request, req);
    _putSendData(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestPATCH(
      HttpClient client, HttpRequest request, Uri uri) async {
    var req = await io.HttpClient()
        .patch(uri.host, uri.port, toPathWithQuery(uri, request));
    _putRequestHeaders(request, req);
    _putSendData(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestDELETE(
      HttpClient client, HttpRequest request, Uri uri) async {
    var req = await io.HttpClient()
        .delete(uri.host, uri.port, toPathWithQuery(uri, request));
    _putRequestHeaders(request, req);
    _putSendData(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestHEAD(
      HttpClient client, HttpRequest request, Uri uri) async {
    var req = await io.HttpClient()
        .head(uri.host, uri.port, toPathWithQuery(uri, request));
    _putRequestHeaders(request, req);
    return req;
  }

  ////////////////////////////////

  void _putSendData(HttpRequest request, io.HttpClientRequest req) {
    if (request.sendData != null) {
      req.write(request.sendData);
    }
  }

  void _putRequestHeaders(HttpRequest request, io.HttpClientRequest req) {
    if (request.requestHeaders != null && request.requestHeaders.isNotEmpty) {
      for (var header in request.requestHeaders.keys) {
        var val = request.requestHeaders[header];
        req.headers.add(header, val);
      }
    }
  }

  ////////////////////////////////

  String toPathWithQuery(Uri uri, HttpRequest request) {
    var queryParameters = request.queryParameters;
    if (queryParameters != null && queryParameters.isEmpty) {
      queryParameters = null;
    }

    if (!uri.hasQuery && queryParameters == null) {
      return uri.path;
    }

    if (queryParameters != null) {
      String query;

      if (uri.hasQuery) {
        // ignore: omit_local_variable_types
        Map<String, String> allParams = Map.from(queryParameters);
        allParams.addAll(uri.queryParameters);
        query = _buildQueryString(allParams);
      } else {
        query = _buildQueryString(queryParameters);
      }

      return '${uri.path}?$query';
    } else {
      return '${uri.path}?${uri.query}';
    }
  }

  io.ContentType toContentType(String contentType) {
    if (contentType == null) return null;
    contentType = contentType.trim();
    if (contentType.isEmpty) return null;

    var parts = contentType.split('/');
    var a = parts[0];
    var b = parts[1];
    return io.ContentType(a, b);
  }

  String _buildQueryString(Map<String, String> params) {
    var query = '';

    for (var key in params.keys) {
      var val = params[key];

      key = Uri.encodeFull(key);
      val = Uri.encodeFull(val);

      if (query.isNotEmpty) query += '&';
      query += '$key=$val';
    }

    return query;
  }
}

HttpClientRequester createHttpClientRequesterImpl() {
  return HttpClientRequesterIO();
}

Uri getHttpClientRuntimeUriImpl() {
  return Uri(scheme: 'http', host: 'localhost', port: 80);
}
