import 'dart:async';
import 'dart:convert';
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
      _ioClient.userAgent = dartAgent.isNotEmpty
          ? '$dartAgent ($mercuryAgent)'
          : mercuryAgent;
    }
  }

  @override
  void close() {
    _ioClient.close();
  }

  @override
  Future<HttpResponse> doHttpRequest(
    HttpClient client,
    HttpRequest request,
    ProgressListener? progressListener,
    bool log,
  ) async {
    var uri = Uri.parse(request.requestURL);

    if (log) {
      this.log('REQUEST: $request > URI: $uri');
    }

    var req = await _request(client, request, uri);
    var response = await req.close();

    return _processResponse(
      client,
      request,
      uri,
      response,
      progressListener,
      log,
    );
  }

  Future<HttpResponse> _processResponse(
    HttpClient client,
    HttpRequest request,
    Uri requestURI,
    io.HttpClientResponse response,
    ProgressListener? progressListener,
    bool log,
  ) async {
    var contentType = response.headers.contentType;

    var body = await _decodeBody(
      request,
      response,
      contentType,
      progressListener,
    );

    var responseHeaders = await _decodeHeaders(response);

    var redirects = response.redirects.map((e) => e.location).toList();

    var resp = HttpResponse(
      request.method,
      request.url,
      requestURI.toString(),
      response.statusCode,
      body,
      responseHeaderGetter: (key) => responseHeaders[key.toLowerCase()],
      request: response,
      redirects: redirects,
      jsonDecoder: client.jsonDecoder,
    );

    if (log) {
      this.log('RESPONSE: $resp');
    }

    var responseHeaderWithToken = client.responseHeaderWithToken;

    if (responseHeaderWithToken != null) {
      var accessToken = resp.getResponseHeader(responseHeaderWithToken);
      if (accessToken != null && accessToken.isNotEmpty) {
        client.authorization = Authorization.fromCredential(
          BearerCredential(accessToken),
        );
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
    ProgressListener? progressListener,
  ) async {
    var mimeType = contentType != null
        ? MimeType.parse(contentType.toString())
        : null;
    var statusCode = response.statusCode;

    var irrelevantContent = (statusCode >= 300 && statusCode < 600);

    if (mimeType != null &&
        (mimeType.isStringType || mimeType.charset != null)) {
      String? s = await _decodeBodyAsString(
        request,
        response,
        mimeType,
        progressListener,
      );

      if (statusCode == 204 || (irrelevantContent && s.isEmpty)) {
        s = null;
      }

      return HttpBody.from(s, mimeType);
    }

    Uint8List? bytes = await _decodeBodyAsBytes(
      request,
      response,
      progressListener,
    );

    if (statusCode == 204 || (irrelevantContent && bytes.isEmpty)) {
      bytes = null;
    }

    return HttpBody.from(bytes, mimeType);
  }

  /// Reads the body bytes, in chunks (not copied), calling [progressListener]
  /// with the bytes loaded and the `Content-Length` (`null` if unknown).
  Future<Uint8List> _decodeBodyAsBytes(
    HttpRequest request,
    io.HttpClientResponse response,
    ProgressListener? progressListener,
  ) async {
    var bytes = BytesBuilder(copy: false);

    if (progressListener != null) {
      var contentLength = response.contentLength;
      var total = contentLength >= 0 ? contentLength : null;

      await for (var chunk in response) {
        bytes.add(chunk);
        try {
          var loaded = bytes.length;
          var ratio = total != null && total > 0 ? loaded / total : null;
          progressListener(request, loaded, total, ratio, false);
        } catch (ex, st) {
          print(ex);
          print(st);
        }
      }
    } else {
      await for (var chunk in response) {
        bytes.add(chunk);
      }
    }

    return bytes.takeBytes();
  }

  Future<String> _decodeBodyAsString(
    HttpRequest request,
    io.HttpClientResponse response,
    MimeType mimeType,
    ProgressListener? progressListener,
  ) async {
    var bytes = await _decodeBodyAsBytes(request, response, progressListener);
    if (bytes.isEmpty) return '';
    return contentTypeToDecoder(mimeType).convert(bytes);
  }

  Future<Map<String, String>> _decodeHeaders(io.HttpClientResponse r) async {
    var headers = <String, String>{};

    // A header with many values is joined with `, ` (as a browser does).
    r.headers.forEach((key, values) {
      headers[key] = values.length == 1 ? values[0] : values.join(', ');
    });

    return headers;
  }

  ////////////////////////////////

  Future<io.HttpClientRequest> _request(
    HttpClient client,
    HttpRequest request,
    Uri uri,
  ) async {
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
      case HttpMethod.OPTIONS:
        return _requestOPTIONS(_ioClient, client, request, uri);
    }
  }

  Future<io.HttpClientRequest> _requestOPTIONS(
    io.HttpClient ioClient,
    HttpClient client,
    HttpRequest request,
    Uri url,
  ) async {
    var req = await ioClient.openUrl('OPTIONS', url);
    _putRequestHeaders(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestGET(
    io.HttpClient ioClient,
    HttpClient client,
    HttpRequest request,
    Uri url,
  ) async {
    var req = await ioClient.getUrl(url);
    _putRequestHeaders(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestPOST(
    io.HttpClient ioClient,
    HttpClient client,
    HttpRequest request,
    Uri url,
  ) async {
    var req = await ioClient.postUrl(url);
    _putRequestHeaders(request, req);
    _putSendData(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestPUT(
    io.HttpClient ioClient,
    HttpClient client,
    HttpRequest request,
    Uri url,
  ) async {
    var req = await ioClient.putUrl(url);
    _putRequestHeaders(request, req);
    _putSendData(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestPATCH(
    io.HttpClient ioClient,
    HttpClient client,
    HttpRequest request,
    Uri url,
  ) async {
    var req = await ioClient.patchUrl(url);
    _putRequestHeaders(request, req);
    _putSendData(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestDELETE(
    io.HttpClient ioClient,
    HttpClient client,
    HttpRequest request,
    Uri url,
  ) async {
    var req = await ioClient.deleteUrl(url);
    _putRequestHeaders(request, req);
    _putSendData(request, req);
    return req;
  }

  Future<io.HttpClientRequest> _requestHEAD(
    io.HttpClient ioClient,
    HttpClient client,
    HttpRequest request,
    Uri url,
  ) async {
    var req = await ioClient.headUrl(url);
    _putRequestHeaders(request, req);
    return req;
  }

  ////////////////////////////////

  void _putSendData(HttpRequest request, io.HttpClientRequest req) {
    var sendData = request.sendData;
    if (sendData is HttpBlob) sendData = sendData.blob;

    if (sendData != null) {
      if (sendData is Uint8List) {
        req.add(sendData);
      } else if (sendData is TypedData) {
        req.add(
          sendData.buffer.asUint8List(
            sendData.offsetInBytes,
            sendData.lengthInBytes,
          ),
        );
      } else if (sendData is List<int>) {
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
  HttpBlobIO(super.blob, super.mimeType);

  @override
  int size() => blob.lengthInBytes;

  @override
  Future<ByteBuffer> readByteBuffer() async {
    var blob = this.blob;
    if (blob.offsetInBytes == 0 &&
        blob.lengthInBytes == blob.buffer.lengthInBytes) {
      return blob.buffer;
    }
    return Uint8List.fromList(
      blob.buffer.asUint8List(blob.offsetInBytes, blob.lengthInBytes),
    ).buffer;
  }
}

/// Creates a [HttpBlobIO] from [content]: a [TypedData], or a [List] of
/// parts ([HttpBlobIO], [String] (UTF-8), [ByteBuffer], [TypedData] or a
/// [List] of bytes).
HttpBlob? createHttpBlobImpl(Object? content, MimeType? mimeType) {
  if (content == null) return null;
  if (content is HttpBlob) return content;
  if (content is TypedData) return HttpBlobIO(content, mimeType);

  var parts = content is List ? content : [content];
  if (parts.length == 1 && parts.first is TypedData) {
    return HttpBlobIO(parts.first as TypedData, mimeType);
  }

  var bytes = BytesBuilder(copy: false);
  for (var part in parts) {
    if (part is HttpBlob) part = part.blob;

    if (part is TypedData) {
      bytes.add(
        part.buffer.asUint8List(part.offsetInBytes, part.lengthInBytes),
      );
    } else if (part is ByteBuffer) {
      bytes.add(part.asUint8List());
    } else if (part is List<int>) {
      bytes.add(part);
    } else if (part != null) {
      bytes.add(utf8.encode('$part'));
    }
  }

  return HttpBlobIO(bytes.takeBytes(), mimeType);
}

bool isHttpBlobImpl(Object? o) => o is HttpBlob;
