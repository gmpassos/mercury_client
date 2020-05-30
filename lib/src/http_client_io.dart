import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'http_client.dart';

/// HttpClientRequester implementation for VM [dart:io].
class HttpClientRequesterIO extends HttpClientRequester {
  io.HttpClient _ioClient;

  HttpClientRequesterIO() {
    _ioClient = io.HttpClient();
    _setupMercuryUserAgent();
  }

  void _setupMercuryUserAgent() {
    var dartAgent = (_ioClient.userAgent ?? '').trim();
    var mercuryAgent = 'mercury_client';
    _ioClient.userAgent =
        dartAgent.isNotEmpty ? '$dartAgent ($mercuryAgent)' : mercuryAgent;
  }

  @override
  void close() {
    _ioClient.close();
  }

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
        return _requestGET(_ioClient, client, request, uri);
      case HttpMethod.POST:
        return _requestPOST(_ioClient, client, request, uri);
      case HttpMethod.PUT:
        return _requestPUT(_ioClient, client, request, uri);
      case HttpMethod.PATCH:
        return _requestPATCH(_ioClient, client, request, uri);
      case HttpMethod.DELETE:
        return _requestDELETE(_ioClient, client, request, uri);
      case HttpMethod.HEAD:
        return _requestHEAD(_ioClient, client, request, uri);
      default:
        throw UnsupportedError("Can't handle method: $method");
    }
  }

  Future<io.HttpClientRequest> _requestGET(io.HttpClient ioClient,
      HttpClient client, HttpRequest request, Uri url) async {
    var req = await ioClient.getUrl(url);
    _putRequestHeaders(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestPOST(io.HttpClient ioClient,
      HttpClient client, HttpRequest request, Uri url) async {
    var req = await ioClient.postUrl(url);
    _putRequestHeaders(request, req);
    _putSendData(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestPUT(io.HttpClient ioClient,
      HttpClient client, HttpRequest request, Uri url) async {
    var req = await ioClient.putUrl(url);
    _putRequestHeaders(request, req);
    _putSendData(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestPATCH(io.HttpClient ioClient,
      HttpClient client, HttpRequest request, Uri url) async {
    var req = await ioClient.patchUrl(url);
    _putRequestHeaders(request, req);
    _putSendData(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestDELETE(io.HttpClient ioClient,
      HttpClient client, HttpRequest request, Uri url) async {
    var req = await ioClient.deleteUrl(url);
    _putRequestHeaders(request, req);
    _putSendData(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestHEAD(io.HttpClient ioClient,
      HttpClient client, HttpRequest request, Uri url) async {
    var req = await ioClient.headUrl(url);
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
}

HttpClientRequester createHttpClientRequesterImpl() {
  return HttpClientRequesterIO();
}

Uri getHttpClientRuntimeUriImpl() {
  return Uri(scheme: 'http', host: 'localhost', port: 80);
}
