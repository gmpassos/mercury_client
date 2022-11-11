import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:swiss_knife/swiss_knife.dart';

import 'http_client.dart';

/// HttpClientRequester implementation for VM [dart:io].
class HttpClientRequesterIO extends HttpClientRequester {
  late final io.HttpClient _ioClient;

  late final String _initialUserAgent;

  HttpClientRequesterIO() {
    _ioClient = io.HttpClient();
    _initialUserAgent = _ioClient.userAgent?.trim() ?? '';
    _setupMercuryUserAgent();
  }

  @override
  bool setupUserAgent(String? userAgent) {
    _setupMercuryUserAgent(userAgent);
    return true;
  }

  @override
  void stdout(Object? o) => io.stdout.writeln(o);

  @override
  void stderr(Object? o) => io.stderr.writeln(o);

  void _setupMercuryUserAgent([String? userAgent]) {
    if (userAgent != null) {
      _ioClient.userAgent = userAgent;
    } else {
      var dartAgent = _initialUserAgent;
      var mercuryAgent = 'mercury_client';
      _ioClient.userAgent =
          dartAgent.isNotEmpty ? '$dartAgent ($mercuryAgent)' : mercuryAgent;
    }
  }

  @override
  void close() {
    _ioClient.close();
  }

  @override
  Future<HttpResponse> doHttpRequest(HttpClient client, HttpRequest request,
      ProgressListener? progressListener, bool log) async {
    var uri = Uri.parse(request.requestURL);

    if (log) {
      this.log('REQUEST: $request > URI: $uri');
    }

    var req = await _request(client, request, uri);
    var response = await req.close();

    return _processResponse(
        client, request, uri, response, progressListener, log);
  }

  Future<HttpResponse> _processResponse(
      HttpClient client,
      HttpRequest request,
      Uri requestURI,
      io.HttpClientResponse response,
      ProgressListener? progressListener,
      bool log) async {
    var contentType = response.headers.contentType;

    var body =
        await _decodeBody(request, response, contentType, progressListener);

    var responseHeaders = await _decodeHeaders(response);

    var resp = HttpResponse(request.method, request.url, requestURI.toString(),
        response.statusCode, body,
        responseHeaderGetter: (key) => responseHeaders[key.toLowerCase()],
        request: response,
        jsonDecoder: client.jsonDecoder);

    if (log) {
      this.log('RESPONSE: $resp');
    }

    var responseHeaderWithToken = client.responseHeaderWithToken;

    if (responseHeaderWithToken != null) {
      var accessToken = resp.getResponseHeader(responseHeaderWithToken);
      if (accessToken != null && accessToken.isNotEmpty) {
        client.authorization =
            Authorization.fromCredential(BearerCredential(accessToken));
      }
    }

    var responseProcessor = client.responseProcessor;

    if (responseProcessor != null) {
      try {
        responseProcessor(client, response, resp);
      } catch (e) {
        print(e);
      }
    }

    return resp;
  }

  ////////////////////////////////

  Future<HttpBody?> _decodeBody(
      HttpRequest request,
      io.HttpClientResponse response,
      io.ContentType? contentType,
      ProgressListener? progressListener) async {
    var mimeType =
        contentType != null ? MimeType.parse(contentType.toString()) : null;
    var statusCode = response.statusCode;

    var irrelevantContent = (statusCode >= 300 && statusCode < 600);

    if (mimeType != null &&
        (mimeType.isStringType || mimeType.charset != null)) {
      String? s = await _decodeBodyAsString(
          request, response, mimeType, progressListener);

      if (statusCode == 204 || (irrelevantContent && s.isEmpty)) {
        s = null;
      }

      return HttpBody.from(s, mimeType);
    }

    List<int>? bytes =
        await _decodeBodyAsBytes(request, response, progressListener);

    if (statusCode == 204 || (irrelevantContent && bytes.isEmpty)) {
      bytes = null;
    }

    return HttpBody.from(bytes, mimeType);
  }

  Future<List<int>> _decodeBodyAsBytes(
      HttpRequest request,
      io.HttpClientResponse response,
      ProgressListener? progressListener) async {
    if (progressListener != null) {
      var total = response.contentLength;
      var loaded = 0;

      return await response.expand((e) {
        try {
          loaded += e.length;
          progressListener(request, loaded, total, loaded / total, false);
        } catch (ex, st) {
          print(ex);
          print(st);
        }
        return e;
      }).toList();
    } else {
      return await response.expand((e) => e).toList();
    }
  }

  Future<String> _decodeBodyAsString(
      HttpRequest request,
      io.HttpClientResponse response,
      MimeType mimeType,
      ProgressListener? progressListener) async {
    var decoder = contentTypeToDecoder(mimeType);

    if (progressListener != null) {
      var total = response.contentLength;
      var loaded = 0;

      return decoder.bind(response).map((e) {
        try {
          loaded += e.length;
          progressListener(request, loaded, total, loaded / total, false);
        } catch (ex, st) {
          print(ex);
          print(st);
        }
        return e;
      }).join();
    } else {
      return decoder.bind(response).join();
    }
  }

  Future<Map<String, String>> _decodeHeaders(io.HttpClientResponse r) async {
    var headers = <String, String>{};

    r.headers.forEach((key, values) {
      headers[key] = values.isNotEmpty ? values[0] : '';
    });

    return headers;
  }

  ////////////////////////////////

  Future<io.HttpClientRequest> _request(
      HttpClient client, HttpRequest request, Uri uri) async {
    var method = request.method;

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
    var sendData = request.sendData;
    if (sendData != null) {
      if (sendData is List<int>) {
        req.add(sendData);
      } else if (sendData is ByteBuffer) {
        req.add(sendData.asUint8List());
      } else {
        req.write(sendData);
      }
    }
  }

  void _putRequestHeaders(HttpRequest request, io.HttpClientRequest req) {
    var requestHeaders = request.requestHeaders;
    if (requestHeaders != null && requestHeaders.isNotEmpty) {
      for (var header in requestHeaders.keys) {
        var val = requestHeaders[header];
        if (val != null) {
          req.headers.add(header, val, preserveHeaderCase: true);
        }
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

class HttpBlobIO extends HttpBlob<TypedData> {
  HttpBlobIO(TypedData blob, MimeType? mimeType) : super(blob, mimeType);

  @override
  int size() => blob.lengthInBytes;

  @override
  Future<ByteBuffer> readByteBuffer() async {
    return blob.buffer;
  }
}

HttpBlob? createHttpBlobImpl(Object? content, MimeType? mimeType) {
  if (content == null) return null;
  if (content is HttpBlob) return content;
  return HttpBlobIO(content as TypedData, mimeType);
}

bool isHttpBlobImpl(Object? o) => o is HttpBlob;
