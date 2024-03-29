import 'dart:async';
import 'dart:typed_data';

import 'package:swiss_knife/swiss_knife.dart';

import 'http_client.dart';

class HttpClientRequesterNone extends HttpClientRequester {
  @override
  bool setupUserAgent(String? userAgent) => false;

  @override
  Future<HttpResponse> doHttpRequest(HttpClient client, HttpRequest request,
      ProgressListener? progressListener, bool log) {
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

class HttpBlobNone extends HttpBlob {
  HttpBlobNone(Object super.blob, super.mimeType);

  @override
  int size() => 0;

  @override
  Future<ByteBuffer> readByteBuffer() {
    throw UnimplementedError();
  }
}

HttpBlob? createHttpBlobImpl(Object? content, MimeType? mimeType) {
  if (content == null) return null;
  if (content is HttpBlob) return content;
  return HttpBlobNone(content, mimeType);
}

bool isHttpBlobImpl(Object? o) => o is HttpBlob;
