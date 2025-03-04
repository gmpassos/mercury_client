import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart' show utf16;
import 'package:collection/collection.dart'
    show IterableExtension, equalsIgnoreAsciiCase;
import 'package:swiss_knife/swiss_knife.dart';

import 'http_client_extension.dart';
import 'http_client_none.dart'
    if (dart.library.io) 'http_client_io.dart'
    if (dart.library.js_interop) 'http_client_browser.dart';

typedef ResponseHeaderGetter = String? Function(String headerKey);

/// Represents a HTTP Status with helpers. Base for [HttpResponse] and [HttpError].
class HttpStatus {
  final String url;

  final String requestedURL;

  final int status;

  HttpStatus(this.url, this.requestedURL, this.status);

  /// Returns [true] if is a successful status.
  bool get isOK => isStatusSuccessful;

  /// Returns [true] if ![isOK]
  bool get isNotOK => !isOK;

  /// Returns [true] if status represents any kind of error.
  bool get isError => isStatusError;

  /// Returns [true] if is a successful status: from range 200 to 299.
  bool get isStatusSuccessful => isStatusInRange(200, 299);

  /// Returns [true] if is 300-303 or 307-308 status (Redirect).
  bool get isStatusRedirect =>
      isStatusInRange(300, 303) || isStatusInRange(307, 308);

  /// Returns [true] if is 404 status (Not Found).
  bool get isStatusNotFound => isStatus(404);

  /// Returns [true] if is 401 status (Unauthenticated).
  bool get isStatusUnauthenticated => isStatus(401);

  /// Returns [true] if is 403 status (Forbidden).
  bool get isStatusForbidden => isStatus(403);

  /// Returns [true] if any network error happens.
  bool get isStatusNetworkError => status <= 0;

  /// Returns [true] if is a server error status: from range 500 to 599.
  bool get isStatusServerError => isStatusInRange(500, 599);

  /// Returns [true] if is a Access Error status: 405..418 OR IN [400, 403, 431, 451].
  bool get isStatusAccessError =>
      isStatusInRange(405, 418) || isStatusInList([400, 403, 431, 451]);

  /// Returns [true] if any error happens: [isStatusNetworkError] || [isStatusServerError] || [isStatusAccessError]
  bool get isStatusError =>
      isStatusNetworkError || isStatusServerError || isStatusAccessError;

  /// Returns [true] if this status is equals parameter [status].
  bool isStatus(int status) {
    return this.status == status;
  }

  /// Returns [true] if this status is in range of parameters [statusInit] and [statusEnd].
  bool isStatusInRange(int statusInit, int statusEnd) {
    return status >= statusInit && status <= statusEnd;
  }

  /// Returns [true] if this status is in [statusList].
  bool isStatusInList(List<int> statusList) {
    return (statusList.firstWhereOrNull((id) => id == status) != null);
  }
}

/// Implements an [HttpStatus] and delegates to [httpStatus].
mixin WithHttpStatus implements HttpStatus {
  HttpStatus get httpStatus;

  @override
  bool get isError => httpStatus.isError;

  @override
  bool get isNotOK => httpStatus.isNotOK;

  @override
  bool get isOK => httpStatus.isOK;

  @override
  bool isStatus(int status) => httpStatus.isStatus(status);

  @override
  bool get isStatusAccessError => httpStatus.isStatusAccessError;

  @override
  bool get isStatusError => httpStatus.isStatusError;

  @override
  bool get isStatusForbidden => httpStatus.isStatusForbidden;

  @override
  bool isStatusInList(List<int> statusList) =>
      httpStatus.isStatusInList(statusList);

  @override
  bool isStatusInRange(int statusInit, int statusEnd) =>
      httpStatus.isStatusInRange(statusInit, statusEnd);

  @override
  bool get isStatusNetworkError => httpStatus.isStatusNetworkError;

  @override
  bool get isStatusNotFound => httpStatus.isStatusNotFound;

  @override
  bool get isStatusRedirect => httpStatus.isStatusRedirect;

  @override
  bool get isStatusServerError => httpStatus.isStatusServerError;

  @override
  bool get isStatusSuccessful => httpStatus.isStatusSuccessful;

  @override
  bool get isStatusUnauthenticated => httpStatus.isStatusUnauthenticated;

  @override
  String get requestedURL => httpStatus.requestedURL;

  @override
  int get status => httpStatus.status;

  @override
  String get url => httpStatus.url;
}

/// Represents a response Error.
class HttpError extends Error with WithHttpStatus {
  @override
  final HttpStatus httpStatus;

  /// The error message, for better understanding than [error].
  final String message;

  /// The actual error thrown by the client.
  final Object? error;

  HttpError(
      String url, String requestedURL, int status, this.message, this.error)
      : httpStatus = HttpStatus(url, requestedURL, status);

  /// If has the field [message]
  bool get hasMessage => message.isNotEmpty;

  /// If is an OAuth Authorization Error. Only if response contains a JSON
  /// with matching entries and status is: 0, 400 or 401.
  ///
  /// Since OAuth uses status 400 to return an Authorization error, this is
  /// useful to identify that.
  bool get isOAuthAuthorizationError {
    if (!hasMessage) return false;

    var authorizationCode = status == 0 || status == 400 || status == 401;
    if (!authorizationCode) return false;

    return matchesAnyJSONEntry('error',
        ['invalid_grant', 'invalid_client', 'unauthorized_client'], true);
  }

  bool matchesAnyJSONEntry(String key, List<String> values, bool text) {
    if (key.isEmpty || values.isEmpty || !hasMessage) return false;

    for (var value in values) {
      if (matchesJSONEntry(key, value, text)) return true;
    }

    return false;
  }

  bool matchesJSONEntry(String key, String value, bool text) {
    if (hasMessage && message.contains(key) && message.contains(value)) {
      var entryValue = text ? '"$value"' : value;
      return RegExp('"$key":\\s*$entryValue').hasMatch(message);
    }
    return false;
  }

  @override
  String toString() {
    return 'HttpError{requestedURL: $requestedURL, status: $status, message: $message, error: $error}';
  }
}

abstract class HttpBlob<B> {
  final B blob;

  final MimeType? mimeType;

  HttpBlob(
    this.blob,
    this.mimeType,
  );

  int size();

  Future<ByteBuffer> readByteBuffer();
}

HttpBlob? createHttpBlob(List content, MimeType? mimeType) {
  return createHttpBlobImpl(content, mimeType);
}

bool isHttpBlob(Object o) {
  return isHttpBlobImpl(o);
}

/// A wrapper for multiple types of data body.
class HttpBody {
  final MimeType? mimeType;
  final Object _body;

  static HttpBody? from(Object? body, [MimeType? mimeType]) {
    if (body == null) return null;
    if (body is HttpBody) return body;
    return HttpBody._(body, mimeType);
  }

  HttpBody._(this._body, [this.mimeType]) {
    if (_body is Future) {
      throw ArgumentError("Can't use a `Future` as body value.");
    }
  }

  bool get isString => _body is String;

  bool get isMap => _body is Map;

  bool get isBlob => isHttpBlob(_body);

  bool get isByteBuffer => _body is ByteBuffer;

  bool get isBytesArray => _body is List<int>;

  int get size {
    final body = _body;

    if (body is String) {
      return body.length;
    } else if (body is ByteBuffer) {
      return body.lengthInBytes;
    } else if (body is List<int>) {
      return body.length;
    } else if (isMap) {
      return asString!.length;
    } else if (isBlob) {
      return asBlob!.size();
    } else {
      return 0;
    }
  }

  String? get asString {
    final body = _body;

    if (body is String) {
      return body;
    } else if (body is ByteBuffer) {
      return bytesToString(body.asUint8List(), mimeType);
    } else if (body is List<int>) {
      return bytesToString(body.toUint8List(), mimeType);
    } else if (isMap) {
      return json.encode(body);
    } else {
      return null;
    }
  }

  /// Converts [bytes] using the encoding specified by [mimeType] if provided.
  /// If [mimeType] is `null` or an [Encoding] cannot be determined,
  /// it will attempt to decode using UTF-8, and if that fails, it will
  /// try LATIN-1.
  static String bytesToString(Uint8List bytes, [MimeType? mimeType]) {
    if (mimeType != null) {
      if (mimeType.isCharsetUTF8) {
        return utf8.decode(bytes);
      } else if (mimeType.isCharsetLATIN1) {
        return utf8.decode(bytes);
      } else if (mimeType.isCharsetUTF16) {
        return utf16.decode(bytes);
      } else {
        var encoding = mimeType.preferredStringEncoding;
        if (encoding != null) {
          return encoding.decode(bytes);
        }
      }
    }

    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  ByteBuffer? get asByteBuffer {
    final body = _body;

    if (body is ByteBuffer) {
      return body;
    } else if (body is List<int>) {
      if (body is TypedData) {
        return (body as TypedData).buffer;
      } else {
        return Uint8List.fromList(body).buffer;
      }
    } else if (body is String) {
      return body.toByteBuffer(encoding: mimeType?.preferredStringEncoding);
    } else if (isMap) {
      var s = asString!;
      return s.toByteBuffer();
    }

    return null;
  }

  List<int>? get asByteArray {
    final body = _body;

    if (body is ByteBuffer) {
      return body.asUint8List();
    } else if (body is List<int>) {
      return body.toUint8List();
    } else if (body is String) {
      return body.toUint8List(encoding: mimeType?.preferredStringEncoding);
    } else if (isMap) {
      return asString!.toUint8List();
    }

    return null;
  }

  HttpBlob? get asBlob {
    if (isBlob) {
      if (_body is HttpBlob) return _body;
      return createHttpBlob(_body as List<dynamic>, mimeType);
    } else if (isByteBuffer) {
      return createHttpBlob([_body], mimeType);
    } else if (isBytesArray) {
      return createHttpBlob([_body], mimeType);
    } else if (isString) {
      return createHttpBlob([_body], mimeType);
    } else if (isMap) {
      return createHttpBlob([asString], mimeType);
    }

    return null;
  }

  Future<ByteBuffer?> get asByteBufferAsync async {
    var byteBuffer = asByteBuffer;
    if (byteBuffer != null) return byteBuffer;

    if (isBlob) {
      var blob = _body as HttpBlob;
      return blob.readByteBuffer();
    }

    return null;
  }

  Future<List<int>?> get asByteArrayAsync async {
    var a = asByteArray;
    if (a != null) return a;
    var bytes = await asByteBufferAsync;
    return bytes?.asUint8List();
  }

  Future<String?> get asStringAsync async {
    var s = asString;
    if (s != null) return s;

    var bytes = await asByteBufferAsync;
    if (bytes == null) return null;

    return bytesToString(bytes.asUint8List(), mimeType);
  }

  /// Alias to [asString].
  @override
  String toString() => asString ?? '';
}

/// The response of a [HttpRequest].
class HttpResponse extends HttpStatus implements Comparable<HttpResponse> {
  /// Response Method
  final HttpMethod method;

  /// Response body.
  final HttpBody? _body;

  /// Response error.
  final HttpError? _error;

  /// A getter capable to get a header entry value.
  final ResponseHeaderGetter? _responseHeaderGetter;

  /// Actual request of the client.
  final Object? request;

  /// Returns the series of redirects this request has been through.
  /// The list will be empty if no redirects were followed.
  final List<Uri> redirects;

  /// Time of instantiation.
  final int instanceTime = DateTime.now().millisecondsSinceEpoch;

  /// The [instanceTime] as [DateTime].
  DateTime get instanceDateTime =>
      DateTime.fromMillisecondsSinceEpoch(instanceTime);

  int? _accessTime;

  /// The JSON decoder [Function] to use (optional).
  dynamic Function(String jsonEncoded)? jsonDecoder;

  HttpResponse(
      this.method, String url, String requestedURL, int status, HttpBody? body,
      {ResponseHeaderGetter? responseHeaderGetter,
      this.request,
      List<Uri>? redirects,
      this.jsonDecoder,
      HttpError? error})
      : _body = body,
        _error = error,
        _responseHeaderGetter = responseHeaderGetter,
        redirects = redirects ?? [],
        super(url, requestedURL, status) {
    _accessTime = instanceTime;
  }

  /// Last access time of this request. Used for caches timeout.
  int? get accessTime => _accessTime;

  void updateAccessTime() {
    _accessTime = DateTime.now().millisecondsSinceEpoch;
  }

  /// Tries to determine the memory usage of this response.
  int memorySize() {
    var memory = 1 +
        8 +
        8 +
        4 +
        (_body != null ? _body.size : 0) +
        (url == requestedURL ? url.length : url.length + requestedURL.length);
    return memory;
  }

  /// Returns the redirect `location` header, the redirect that should be performed.
  /// - See [isStatusRedirect].
  /// - See [redirects] for previous redirected locations.
  String? get redirectToLocation => getResponseHeader('location');

  /// The response [HttpError].
  HttpError? get error => _error;

  /// Returns the response [HttpBody].
  HttpBody? get body => _body;

  /// Returns the [body] as [String].
  String? get bodyAsString {
    var body = _body;
    return body != null && body.size > 0 ? body.asString : null;
  }

  /// Returns the [body] `length` (if present).
  int? get bodyLength => _body?.size;

  /// Returns the [body] as JSON.
  dynamic get json => _jsonDecode(bodyAsString);

  dynamic _jsonDecode(String? s) {
    if (s == null || s.isEmpty) return null;

    var jsonDecoder = this.jsonDecoder;
    if (jsonDecoder != null) {
      return jsonDecoder(s);
    } else {
      return jsonDecode(s);
    }
  }

  /// Returns [true] if has [body].
  bool get hasBody {
    var body = _body;
    return body != null && body.size > 0;
  }

  /// The [body] type (Content-Type).
  String? get bodyType => getResponseHeader(HttpRequest._headerKeyContentType);

  /// Same as [bodyType], but returns as [MimeType].
  MimeType? get bodyMimeType {
    return MimeType.parse(bodyType);
  }

  /// Returns [true] if [bodyType] is a JSON (application/json).
  bool get isBodyTypeJSON {
    var mimeType = bodyMimeType;
    if (mimeType == null) return false;
    return mimeType.isJSON || mimeType.isJavascript;
  }

  /// Returns [body] as a [JSONPaging].
  JSONPaging? get asJSONPaging {
    if (isBodyTypeJSON) {
      return JSONPaging.from(json);
    }
    return null;
  }

  /// Returns the header value for the parameter [headerKey].
  String? getResponseHeader(String headerKey) {
    if (_responseHeaderGetter == null) return null;

    try {
      return _responseHeaderGetter(headerKey);
    } catch (e, s) {
      print("[HttpResponse] Can't access response header: $headerKey");
      print(e);
      print(s);
      return null;
    }
  }

  @override
  String toString([bool? withBody]) {
    withBody ??= false;
    var infos = 'status: $status, method: $method, requestedURL: $requestedURL';

    if (withBody) {
      var bodyStr = bodyAsString;
      if (bodyStr != null) {
        infos += ', body: $bodyAsString';
      }
    } else {
      var bodyLength = this.bodyLength;
      if (bodyLength != null) {
        infos += ', body: $bodyLength bytes';
      }
    }
    return 'HttpResponse{ $infos }';
  }

  /// Compares using [instanceTime].
  @override
  int compareTo(HttpResponse other) {
    return instanceTime < other.instanceTime
        ? -1
        : (instanceTime == other.instanceTime ? 0 : 1);
  }
}

/// Function to dynamically build a HTTP body.
typedef HttpBodyBuilder = dynamic Function(Map<String, String?> parameters);
typedef HttpBodyBuilderTyped = dynamic Function(
    Map<String, String?> parameters, String? type);

/// Represents a body content, used by [HttpRequest].
class HttpRequestBody {
  // ignore: non_constant_identifier_names
  static final HttpRequestBody NULL = HttpRequestBody(null, null);

  /// Normalizes a Content-Type, allowing aliases like: json, png, jpeg and javascript.
  static String? normalizeType(String? bodyType) {
    return MimeType.parseAsString(bodyType);
  }

  ////////

  HttpBody? _content;

  String? _contentType;

  HttpRequestBody(Object? content, String? type,
      [Map<String, Object?>? parameters]) {
    _contentType = normalizeType(type);

    var parametersMapStr = _toParametersMapOfString(parameters);

    if (content is HttpBodyBuilder) {
      var f = content;
      content = f(parametersMapStr ?? {});
    } else if (content is HttpBodyBuilderTyped) {
      var f = content;
      content = f(parametersMapStr ?? {}, _contentType);
    } else if (content is Function) {
      var f = content;
      content = f();
    }

    if (content == null) {
      _content = null;
    } else if (content is HttpBody) {
      _content = content;
    } else if (!isJSONType && content is List<int>) {
      _content = HttpBody.from(content, MimeType.parse(_contentType));
    } else if (content is String) {
      _content = HttpBody.from(content, MimeType.parse(_contentType));
    } else if (isJSONType ||
        (_contentType == null && (content is Map || content is List))) {
      _contentType ??= MimeType.applicationJson;
      var jsonEncoded = encodeJSON(content);
      _content = HttpBody.from(jsonEncoded, MimeType.parse(_contentType));
    } else {
      _content =
          HttpBody.from(content.toString(), MimeType.parse(_contentType));
    }
  }

  /// Content of the body.
  String? get contentAsString {
    return _content?.asString;
  }

  dynamic get contentAsSendData {
    var content = _content;
    if (content == null) return null;
    if (content.isString) return content.asString;
    if (content.isByteBuffer) return content.asByteBuffer;
    if (content.isBytesArray) return content.asByteArray;
    if (content.isBlob) return content.asBlob!.blob;
    return content.asString;
  }

  /// Type of the body (Content-Type header).
  String? get contentType => _contentType;

  /// Returns [true] if has content.
  bool get hasContent => _content != null;

  /// Returns [true] if has no content.
  bool get hasNoContent => _content == null;

  /// Returns [true] if has no [contentType].
  bool get hasNoContentType => _contentType == null;

  /// Returns [true] if [contentType] is a JSON (application/json).
  bool get isJSONType =>
      _contentType != null && _contentType!.endsWith('/json');

  /// Returns [true] if [hasNoContent] and [hasNoContentType].
  bool get isNull => hasNoContent && hasNoContentType;
}

typedef RequestHeadersBuilder = Map<String, String> Function(
    HttpClient client, String url);

typedef ResponseProcessor = void Function(
    HttpClient client, Object request, HttpResponse response);

typedef AuthorizationProvider = Future<Credential?> Function(
    HttpClient client, HttpError? lastError);

/// Represents a kind of HTTP Authorization.
abstract class Authorization {
  /// Copies this instance.
  Authorization copy();

  /// Returns [true] if the [Credential] is already resolved.
  bool get isCredentialResolved;

  /// Returns [true] if resolved [Credential] uses `Authorization` HTTP header.
  bool get usesAuthorizationHeader =>
      isCredentialResolved && resolvedCredential!.usesAuthorizationHeader;

  /// Returns the resolved [Credential].
  ///
  /// Throws [StateError] if not resolved.
  Credential? get resolvedCredential;

  /// Returns [true] if the [Credential] is static
  /// (future calls to [resolveCredential] will return the same instance).
  bool get isStaticCredential;

  /// Returns the resolved [Credential] or [null] if not resolved.
  Credential? get tryResolvedCredential;

  /// Returns [true] if is in the process of [Credential] resolution.
  bool get isResolvingCredential => false;

  /// Resolves the actual [Credential] for the [HttpRequest].
  /// This method should cache the last resolved [Credential]
  /// and avoid unnecessary resolving procedures.
  Future<Credential?> resolveCredential(
      HttpClient client, HttpError? lastError);

  Authorization._();

  /// Constructs a [AuthorizationStatic].
  factory Authorization.fromCredential(Credential credential) {
    return _AuthorizationStatic(credential);
  }

  /// Constructs a [AuthorizationResolvable].
  factory Authorization.fromProvider(AuthorizationProvider provider) {
    return _AuthorizationResolvable(provider);
  }
}

/// A static [Authorization], with [Credential] already resolved.
class _AuthorizationStatic extends Authorization {
  /// The resolved [Credential].
  final Credential credential;

  _AuthorizationStatic(this.credential) : super._();

  @override
  Authorization copy() => _AuthorizationStatic(credential);

  @override
  bool get isCredentialResolved => true;

  @override
  bool get isStaticCredential => true;

  @override
  Credential get resolvedCredential {
    if (!isCredentialResolved) throw StateError('Credential not resolved');
    return credential;
  }

  @override
  Credential get tryResolvedCredential => credential;

  @override
  Future<Credential> resolveCredential(
          HttpClient client, HttpError? lastError) async =>
      credential;

  @override
  String toString() {
    return 'AuthorizationStatic{credential: $credential}';
  }
}

class _AuthorizationResolvable extends Authorization {
  /// An [AuthorizationProvider]. Used by [Credential] that are provided by
  /// a function.
  final AuthorizationProvider authorizationProvider;

  _AuthorizationResolvable(this.authorizationProvider) : super._();

  /// Copies this instance.
  @override
  Authorization copy() {
    var authorization = _AuthorizationResolvable(authorizationProvider);
    authorization._resolvedCredential = _resolvedCredential;
    return authorization;
  }

  Credential? _resolvedCredential;

  /// Returns [true] if the [Credential] is already resolved.
  @override
  bool get isCredentialResolved => _resolvedCredential != null;

  @override
  bool get isStaticCredential => false;

  @override
  Credential? get resolvedCredential {
    if (!isCredentialResolved) throw StateError('Credential not resolved');
    return _resolvedCredential;
  }

  @override
  Credential? get tryResolvedCredential => _resolvedCredential;

  Future<Credential?>? _resolveFuture;

  @override
  bool get isResolvingCredential => _resolveFuture != null;

  /// Resolve the actual [Credential] for the [HttpRequest].
  @override
  Future<Credential?> resolveCredential(
      HttpClient client, HttpError? lastError) async {
    if (_resolvedCredential != null) return _resolvedCredential;

    if (_resolveFuture != null) {
      try {
        var credential = await _resolveFuture!;
        return _resolvedCredential ?? credential;
      } catch (e) {
        return _resolvedCredential;
      }
    }

    _resolveFuture = authorizationProvider(client, lastError);

    if (_resolveFuture == null) return null;

    Credential? credential;
    try {
      credential = await _resolveFuture;
    } catch (e, s) {
      print(e);
      print(s);
    }

    _resolvedCredential = credential;
    _resolveFuture = null;

    return _resolvedCredential;
  }

  @override
  String toString() {
    return 'AuthorizationResolvable{authorizationProvider: $authorizationProvider}';
  }
}

/// Abstract Credential for [HttpRequest].
abstract class Credential {
  /// The type of the credential.
  String get type;

  /// If this credential uses the header `Authorization`.
  bool get usesAuthorizationHeader;

  /// Builds the header `Authorization`.
  String? buildAuthorizationHeaderLine() {
    return null;
  }

  /// Builds the [HttpRequest] URL. Used by credentials that injects tokens/credentials in the URL.
  String? buildURL(String url) {
    return null;
  }

  /// Builds the [HttpRequest] body. Used by credentials that injects tokens/credentials in the body.
  HttpRequestBody? buildBody(HttpRequestBody body) {
    return null;
  }
}

/// A HTTP Basic Credential for the `Authorization` header.
class BasicCredential extends Credential {
  /// Plain username of the credential.
  final String username;

  /// Plain password of the credential.
  final String password;

  BasicCredential(this.username, this.password);

  static BasicCredential? fromJSON(dynamic json) {
    if (json == null) return null;

    if (json is List) {
      if (json.length < 2) return null;
      var user = json[0];
      var pass = json[1];
      if (user is! String || pass is! String) return null;
      return BasicCredential(user, pass);
    } else if (json is Map) {
      if (json.length < 2) return null;

      var user = findKeyValue<dynamic, dynamic>(
          json, ['username', 'user', 'login', 'email', 'account'], true);
      var pass = findKeyValue<dynamic, dynamic>(
          json, ['password', 'pass', 'secret', 'token'], true);

      if (user is! String || pass is! String) return null;

      return BasicCredential(user, pass);
    } else if (json is String) {
      var parts = json.split(RegExp(r'[:;\s]+'));
      if (parts.length < 2) return null;
      return BasicCredential(parts[0], parts[1]);
    }
    return null;
  }

  /// Instantiate using a base64 encoded credential, in format `$username:$password`.
  factory BasicCredential.base64(String base64) {
    var decodedBytes = Base64Codec.urlSafe().decode(base64);

    String decoded;
    try {
      decoded = utf8.decode(decodedBytes);
    } catch (_) {
      decoded = latin1.decode(decodedBytes);
    }

    var idx = decoded.indexOf(':');

    if (idx < 0) {
      return BasicCredential(decoded, '');
    }

    var user = decoded.substring(0, idx);
    var pass = decoded.substring(idx + 1);

    return BasicCredential(user, pass);
  }

  /// Returns type `Basic`.
  @override
  String get type => 'Basic';

  /// Returns [true].
  @override
  bool get usesAuthorizationHeader => true;

  /// Builds the `Authorization` header.
  @override
  String buildAuthorizationHeaderLine() {
    var payload = '$username:$password';
    var encode = Base64Codec.urlSafe().encode(payload.codeUnits);
    return 'Basic $encode';
  }
}

/// A HTTP Bearer Credential for the `Authorization` header.
class BearerCredential extends Credential {
  /// Finds the token inside a [json] map using the [tokenKey].
  /// [tokenKey] can be a tree path using `/` as node delimiter.
  static dynamic findToken(Map json, String tokenKey) {
    if (json.isEmpty || tokenKey.isEmpty) return null;

    var tokenKeys = tokenKey.split('/');

    dynamic token = findKeyValue(json, [tokenKeys.removeAt(0)], true);
    if (token == null) return null;

    for (var k in tokenKeys) {
      if (token is Map) {
        token = findKeyValue(token, [k], true);
      } else if (token is List && isInt(k)) {
        var idx = parseInt(k);
        token = token[idx!];
      } else {
        token = null;
      }

      if (token == null) return null;
    }

    if (token is String || token is num) {
      return token;
    }

    return null;
  }

  /// The token [String].
  final String token;

  BearerCredential(this.token);

  static const List<String> _defaultExtraTokenKeys = [
    'accessToken',
    'accessToken/token'
  ];

  /// Instance from a JSON.
  ///
  /// [mainTokenKey] default: `access_token`.
  /// [extraTokenKeys]: `accessToken`, `accessToken/token`.
  static BearerCredential? fromJSONToken(dynamic json,
      [String mainTokenKey = 'access_token',
      List<String> extraTokenKeys = _defaultExtraTokenKeys]) {
    if (json is Map) {
      var token =
          findKeyPathValue(json, mainTokenKey, isValidValue: isValidTokenValue);

      if (token == null) {
        for (var key in extraTokenKeys) {
          token = findKeyPathValue(json, key, isValidValue: isValidTokenValue);
          if (token != null) break;
        }
      }

      if (token != null) {
        var tokenStr = token.toString().trim();
        return tokenStr.isNotEmpty ? BearerCredential(tokenStr) : null;
      }
    }

    return null;
  }

  /// Returns [true] if the token is a valid value.
  static bool isValidTokenValue(v) => v is String || v is num;

  /// Returns type `Bearer`.
  @override
  String get type => 'Bearer';

  /// Returns [true].
  @override
  bool get usesAuthorizationHeader => true;

  /// Builds the `Authorization` header.
  @override
  String buildAuthorizationHeaderLine() {
    return 'Bearer $token';
  }
}

/// A [Credential] that injects fields in the Query parameters.
class QueryStringCredential extends Credential {
  /// The Credential tokes. Usually: `{'access_token': 'the_toke_string'}`s
  final Map<String, String> fields;

  QueryStringCredential(this.fields);

  /// Returns `queryString`.
  @override
  String get type => 'queryString';

  /// Returns [false].
  @override
  bool get usesAuthorizationHeader => false;

  /// Builds the [HttpRequest] URL.
  @override
  String buildURL(String url) {
    return buildURLWithQueryParameters(url, fields, removeFragment: true);
  }
}

/// A [Credential] that injects a JSON in the [HttpRequest] body.
class JSONBodyCredential extends Credential {
  /// JSON field with [authorization] value.
  String? _field;

  /// Authorization JSON tree.
  final dynamic authorization;

  JSONBodyCredential(String field, this.authorization) {
    field = field.trim();
    _field = field.isNotEmpty ? field : null;
  }

  /// JSON field name.
  String? get field => _field;

  /// Returns `jsonbody`.
  @override
  String get type => 'jsonbody';

  /// Returns [false].
  @override
  bool get usesAuthorizationHeader => false;

  @override
  String? buildAuthorizationHeaderLine() {
    return null;
  }

  /// Won't change the parameter [url].
  @override
  String buildURL(String url) {
    return url;
  }

  /// Builds the [HttpRequest] body with the [Credential].
  @override
  HttpRequestBody buildBody(HttpRequestBody body) {
    if (body.isNull) {
      return buildJSONAuthorizationBody(null);
    } else if (body.isJSONType) {
      return buildJSONAuthorizationBody(body);
    } else {
      return body;
    }
  }

  HttpRequestBody buildJSONAuthorizationBody(HttpRequestBody? body) {
    return HttpRequestBody(
        buildJSONAuthorizationBodyJSON(body), 'application/json');
  }

  String buildJSONAuthorizationBodyJSON(HttpRequestBody? body) {
    if (body == null || body.hasNoContent) {
      if (field == null || field!.isEmpty) {
        return encodeJSON(authorization);
      } else {
        return encodeJSON({field: authorization});
      }
    }

    var bodyJson = json.decode(body.contentAsString!);

    if (field == null || field!.isEmpty) {
      if (authorization is Map) {
        if (bodyJson is Map) {
          bodyJson.addAll(authorization);
        } else {
          throw StateError(
              "No specified field for authorization. Can't add authorization to current body! Current body is not a Map to receive a Map authorization.");
        }
      } else if (authorization is List) {
        if (bodyJson is List) {
          bodyJson.addAll(authorization);
        } else {
          throw StateError(
              "No specified field for authorization. Can't add authorization to current body! Current body is not a List to receive a List authorization.");
        }
      } else {
        throw StateError(
            "No specified field for authorization. Can't add authorization to current body! authorization is not a Map or List to add to any type of body.");
      }
    } else {
      bodyJson[field] = authorization;
    }

    return encodeJSON(bodyJson);
  }
}

/// Builds an URL with Query parameters adding the map [parameters] to current
/// Query parameters.
///
/// [removeFragment] If [true] will remove URL fragment.
String buildURLWithQueryParameters(String url, Map<String, String?> parameters,
    {bool removeFragment = false}) {
  if (parameters.isEmpty) return url;

  var uri = Uri.parse(url);

  Map<String, String?> queryParameters;

  if (uri.query.isEmpty) {
    queryParameters = Map<String, String?>.from(parameters);
  } else {
    queryParameters = uri.queryParameters;
    queryParameters = Map<String, String?>.from(queryParameters);
    queryParameters.addAll(parameters);
  }

  String? fragment = uri.fragment;
  if (removeFragment || fragment.isEmpty) {
    fragment = null;
  }

  return Uri(
          scheme: uri.scheme,
          userInfo: uri.userInfo,
          host: uri.host,
          port: uri.port,
          path: Uri.decodeComponent(uri.path),
          queryParameters: queryParameters,
          fragment: fragment)
      .toString();
}

/// HTTP Method
enum HttpMethod {
  // ignore: constant_identifier_names
  GET,
  // ignore: constant_identifier_names
  OPTIONS,
  // ignore: constant_identifier_names
  POST,
  // ignore: constant_identifier_names
  PUT,
  // ignore: constant_identifier_names
  DELETE,
  // ignore: constant_identifier_names
  PATCH,
  // ignore: constant_identifier_names
  HEAD,
}

bool methodAcceptsQueryString(HttpMethod method) {
  return method == HttpMethod.GET || method == HttpMethod.OPTIONS;
}

/// Returns [HttpMethod] instance for [method] parameter.
HttpMethod? getHttpMethod(String? method, [HttpMethod? def]) {
  if (method == null) return def;
  method = method.trim().toUpperCase();
  if (method.isEmpty) return def;

  switch (method) {
    case 'GET':
      return HttpMethod.GET;
    case 'OPTIONS':
      return HttpMethod.OPTIONS;
    case 'POST':
      return HttpMethod.POST;
    case 'PUT':
      return HttpMethod.PUT;
    case 'DELETE':
      return HttpMethod.DELETE;
    case 'PATCH':
      return HttpMethod.PATCH;
    case 'HEAD':
      return HttpMethod.HEAD;
    default:
      return def;
  }
}

bool canHttpMethodHaveBody(HttpMethod method) {
  switch (method) {
    case HttpMethod.POST:
    case HttpMethod.PUT:
    case HttpMethod.PATCH:
      return true;
    default:
      return false;
  }
}

/// Returns [method] name.
String? getHttpMethodName(HttpMethod? method, [HttpMethod? def]) {
  method ??= def!;

  switch (method) {
    case HttpMethod.GET:
      return 'GET';
    case HttpMethod.OPTIONS:
      return 'OPTIONS';
    case HttpMethod.POST:
      return 'POST';
    case HttpMethod.PUT:
      return 'PUT';
    case HttpMethod.DELETE:
      return 'DELETE';
    case HttpMethod.PATCH:
      return 'PATCH';
    case HttpMethod.HEAD:
      return 'HEAD';
  }
}

/// Represents the HTTP request.
class HttpRequest {
  /// HTTP Method.
  final HttpMethod method;

  /// Requested URL.
  final String url;

  /// Actual requested URL.
  final String requestURL;

  /// The query parameters of the request.
  final Map<String, String?>? queryParameters;

  /// If [true] avoid a request URL with a `queryString`.
  final bool noQueryString;

  /// Authorization instance for the request.
  final Authorization? authorization;

  final bool withCredentials;

  /// Tells the server the desired response format.
  final String? responseType;

  /// MimeType of request sent data (body).
  final String? mimeType;

  Map<String, String>? _requestHeaders;

  Object? _sendData;

  int _retries = 0;

  HttpRequest(this.method, this.url, this.requestURL,
      {this.queryParameters,
      this.noQueryString = false,
      this.authorization,
      this.withCredentials = false,
      this.responseType,
      this.mimeType,
      Map<String, String>? requestHeaders,
      Object? sendData})
      : _requestHeaders = requestHeaders,
        _sendData = sendData {
    updateContentLength();
  }

  /// Copies this instance with a different [client] and [authorization] if provided.
  ///
  /// If [authorization] is `null` returns `this`.
  HttpRequest copyWithAuthorization(HttpClient client,
      [Authorization? authorization]) {
    if (authorization == null || authorization == this.authorization) {
      return this;
    }

    var requestHeaders = client.clientRequester.buildRequestHeaders(
        client, method, url,
        headers: this.requestHeaders,
        authorization: authorization,
        contentType: headerContentType,
        accept: headerAccept);

    var queryParameters = this.queryParameters != null
        ? Map<String, String?>.from(this.queryParameters!)
        : null;

    var requestURL = client.clientRequester.buildRequestURL(client, url,
        authorization: authorization,
        queryParameters: queryParameters,
        noQueryString: noQueryString);

    var copy = HttpRequest(
      method,
      url,
      requestURL,
      queryParameters: queryParameters,
      noQueryString: noQueryString,
      authorization: authorization,
      withCredentials: withCredentials,
      responseType: responseType,
      mimeType: mimeType,
      requestHeaders: requestHeaders,
      sendData: sendData,
    );

    copy._retries = _retries;

    return copy;
  }

  /// Headers of the request.
  Map<String, String>? get requestHeaders => _requestHeaders;

  void updateContentLength() {
    var sendDataLength = _sendDataLength(updateToBytes: true);
    if (sendDataLength != null) {
      var contentLength = headerContentLength;
      var transferEncoding = headerTransferEncoding;
      if (contentLength == null &&
          (transferEncoding == null || transferEncoding.contains('chunked'))) {
        var requestHeaders = _requestHeaders ??= <String, String>{};
        requestHeaders[HttpRequest._headerKeyContentLength] = '$sendDataLength';
      }
    }
  }

  /// Data/body to send with the request.
  Object? get sendData => _sendData;

  /// [sendData] length in bytes.
  int? get sendDataLength => _sendDataLength();

  int? _sendDataLength({bool updateToBytes = false}) {
    var sendData = this.sendData;
    if (sendData == null) return null;

    if (sendData is Uint8List) {
      return sendData.length;
    } else if (sendData is List<int>) {
      return sendData.length;
    } else if (sendData is ByteBuffer) {
      return sendData.lengthInBytes;
    } else if (sendData is HttpBlob) {
      return sendData.size();
    } else if (sendData is String) {
      var bytes = sendData.toUint8List(
          encoding: MimeType.parse(mimeType)?.preferredStringEncoding);
      if (updateToBytes) {
        _sendData = bytes;
      }
      return bytes.length;
    }

    return null;
  }

  /// [sendData] as a [String].
  String? get sendDataAsString {
    var sendData = this.sendData;
    if (sendData != null) {
      if (sendData is List<int>) {
        return sendData.decode();
      } else if (sendData is ByteBuffer) {
        return sendData.asUint8List().decode();
      } else {
        return sendData.toString();
      }
    }
    return null;
  }

  /// Returns the header: Accept
  String? get headerAccept =>
      _getMapValueKeyIgnoreCase(requestHeaders, 'Content-Accept');

  static const _headerKeyContentType = 'Content-Type';

  /// Returns the header: Content-Type
  String? get headerContentType =>
      _getMapValueKeyIgnoreCase(requestHeaders, _headerKeyContentType);

  set headerContentType(String? contentType) {
    if (contentType == null) {
      var k = _getMapKeyIgnoreCase(requestHeaders, _headerKeyContentType);
      if (k != null) {
        requestHeaders?.remove(k);
      }
    } else {
      var requestHeaders = _requestHeaders ??= <String, String>{};
      var k = _getMapKeyIgnoreCase(requestHeaders, _headerKeyContentType) ??
          _headerKeyContentType;
      requestHeaders[k] = contentType.trim();
    }
  }

  /// Returns the header `Content-Type` Mime-Type (without the charset).
  String? get headerContentTypeMimeType {
    var contentType = headerContentType;
    if (contentType == null) return null;
    var idx = contentType.indexOf(';');
    if (idx < 0) return contentType.trim();
    var mimeType = contentType.substring(0, idx).trim();
    return mimeType;
  }

  set headerContentTypeMimeType(String? mimeType) {
    if (mimeType == null) {
      headerContentType = null;
      return;
    }

    var contentType = headerContentType;
    var idx = contentType?.indexOf(';') ?? -1;
    if (idx < 0) {
      headerContentType = mimeType.trim();
      return;
    }

    var rest = contentType!.substring(idx + 1).trim();
    contentType =
        rest.isNotEmpty ? '${mimeType.trim()}; $rest' : mimeType.trim();

    headerContentType = contentType;
  }

  /// Returns the header `Content-Type` charset.
  String? get headerContentTypeCharset {
    var contentType = headerContentType;
    if (contentType == null) return null;
    var idx = contentType.indexOf(';');
    if (idx < 0) return null;

    var rest = contentType.substring(idx + 1);
    var parts = rest.split(';').map((e) => e.trim().split('='));
    if (parts.isEmpty) return null;

    var charsetPair =
        parts.firstWhereOrNull((e) => equalsIgnoreAsciiCase(e[0], 'charset'));
    if (charsetPair == null) return null;

    var charset = charsetPair[1].trim();
    return charset;
  }

  set headerContentTypeCharset(String? charset) {
    charset = _normalizeCharset(charset);

    var contentType = headerContentType;
    if (contentType == null) {
      if (charset != null) {
        headerContentType = 'text/plain; charset=$charset';
      }
      return;
    }

    var parts = contentType
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    var charsetEntry = charset != null ? 'charset=$charset' : null;

    if (parts.length == 1) {
      if (charsetEntry != null) {
        parts.add(charsetEntry);
      }
    } else {
      var idx = parts.indexWhere((e) => e.startsWith('charset='));

      if (charsetEntry != null) {
        if (idx >= 0) {
          parts[idx] = charsetEntry;
        } else {
          parts.insert(1, charsetEntry);
        }
      } else if (idx >= 0) {
        parts.removeAt(idx);
      }
    }

    headerContentType = parts.join('; ');
  }

  String? _normalizeCharset(String? charset) {
    if (charset == null) return null;
    charset = charset.trim();
    if (charset.isEmpty) return null;

    if (equalsIgnoreAsciiCase(charset, 'UTF-8') ||
        equalsIgnoreAsciiCase(charset, 'UTF8')) {
      return 'UTF-8';
    } else if (equalsIgnoreAsciiCase(charset, 'LATIN-1') ||
        equalsIgnoreAsciiCase(charset, 'LATIN1') ||
        equalsIgnoreAsciiCase(charset, 'ISO-8859-1')) {
      return 'ISO-8859-1';
    }

    return charset;
  }

  static const _headerKeyContentLength = 'Content-Length';

  /// Returns the header: Content-Length
  String? get headerContentLength =>
      _getMapValueKeyIgnoreCase(requestHeaders, _headerKeyContentLength);

  static const _headerKeyTransferEncoding = 'Transfer-Encoding';

  /// Returns the header: Transfer-Encoding
  String? get headerTransferEncoding =>
      _getMapValueKeyIgnoreCase(requestHeaders, _headerKeyTransferEncoding);

  /// Number of retries for this request.
  int get retries => _retries;

  void incrementRetries() {
    _retries++;
  }

  @override
  String toString() {
    return 'HttpRequest{ method: $method, '
        'url: $url, '
        'requestURL: $requestURL, '
        'retries: $_retries, '
        'queryParameters: $queryParameters, '
        'authorization: $authorization, '
        'withCredentials: $withCredentials, '
        'responseType: $responseType, '
        'mimeType: $mimeType, '
        'requestHeaders: $requestHeaders, '
        'sendData: $sendDataAsString }';
  }
}

typedef ProgressListener = void Function(
    HttpRequest request, int? loaded, int? total, double? ratio, bool upload);

/// Abstract [HttpClient] requester. This should implement the actual
/// request process.
abstract class HttpClientRequester {
  bool setupUserAgent(String? userAgent);

  void stdout(Object? o) => print(o);

  void stderr(Object? o) => stdout(o);

  void log(Object? o) {
    stdout('[HttpClient] $o');
  }

  void logError(Object? message, [Object? error, StackTrace? stackTrace]) {
    if (message != null) {
      stderr('** [HttpClient] ERROR> $message');
    }
    if (error != null) {
      stderr(error);
    }
    if (stackTrace != null) {
      stderr(stackTrace);
    }
  }

  Future<HttpResponse> request(HttpClient client, HttpMethod method, String url,
      {Map<String, String>? headers,
      Authorization? authorization,
      Map<String, String?>? queryParameters,
      bool noQueryString = false,
      Object? body,
      String? contentType,
      String? accept,
      String? responseType,
      ProgressListener? progressListener}) {
    switch (method) {
      case HttpMethod.GET:
        return requestGET(client, url,
            headers: headers,
            authorization: authorization,
            queryParameters: queryParameters,
            noQueryString: noQueryString,
            accept: accept,
            responseType: responseType,
            progressListener: progressListener);
      case HttpMethod.HEAD:
        return requestHEAD(client, url,
            headers: headers,
            authorization: authorization,
            queryParameters: queryParameters,
            noQueryString: noQueryString,
            progressListener: progressListener);
      case HttpMethod.OPTIONS:
        return requestOPTIONS(client, url,
            headers: headers,
            authorization: authorization,
            queryParameters: queryParameters,
            noQueryString: noQueryString,
            progressListener: progressListener);
      case HttpMethod.POST:
        return requestPOST(client, url,
            headers: headers,
            authorization: authorization,
            queryParameters: queryParameters,
            noQueryString: noQueryString,
            body: body,
            contentType: contentType,
            accept: accept,
            responseType: responseType,
            progressListener: progressListener);
      case HttpMethod.PUT:
        return requestPUT(client, url,
            headers: headers,
            authorization: authorization,
            queryParameters: queryParameters,
            noQueryString: noQueryString,
            body: body,
            contentType: contentType,
            accept: accept,
            responseType: responseType,
            progressListener: progressListener);
      case HttpMethod.PATCH:
        return requestPATCH(client, url,
            headers: headers,
            authorization: authorization,
            queryParameters: queryParameters,
            noQueryString: noQueryString,
            body: body,
            contentType: contentType,
            accept: accept,
            responseType: responseType,
            progressListener: progressListener);
      case HttpMethod.DELETE:
        return requestDELETE(client, url,
            headers: headers,
            authorization: authorization,
            queryParameters: queryParameters,
            noQueryString: noQueryString,
            body: body,
            contentType: contentType,
            accept: accept,
            responseType: responseType,
            progressListener: progressListener);
    }
  }

  bool _withCredentials(HttpClient client, Authorization? authorization) {
    if (client.crossSiteWithCredentials != null) {
      return client.crossSiteWithCredentials!;
    }

    if (authorization != null && authorization.usesAuthorizationHeader) {
      return true;
    } else {
      return false;
    }
  }

  Future<HttpResponse> requestGET(HttpClient client, String url,
      {Map<String, String>? headers,
      Authorization? authorization,
      Map<String, String?>? queryParameters,
      bool noQueryString = false,
      String? accept,
      String? responseType,
      ProgressListener? progressListener}) async {
    var requestURL = buildRequestURL(client, url,
        authorization: authorization,
        queryParameters: queryParameters,
        noQueryString: noQueryString);

    var requestHeaders = buildRequestHeaders(client, HttpMethod.GET, url,
        headers: headers, authorization: authorization, accept: accept);

    requestURL = await client._interceptRequest(
        HttpMethod.GET, requestURL, requestHeaders);

    return submitHttpRequest(
        client,
        HttpRequest(HttpMethod.GET, url, requestURL,
            authorization: authorization,
            queryParameters: queryParameters,
            withCredentials: _withCredentials(client, authorization),
            requestHeaders: requestHeaders,
            responseType: responseType),
        progressListener,
        client.logRequests);
  }

  Future<HttpResponse> requestHEAD(HttpClient client, String url,
      {Map<String, String>? headers,
      Authorization? authorization,
      Map<String, String?>? queryParameters,
      bool noQueryString = false,
      ProgressListener? progressListener}) async {
    var requestURL = buildRequestURL(client, url,
        authorization: authorization,
        queryParameters: queryParameters,
        noQueryString: noQueryString);

    var requestHeaders = buildRequestHeaders(client, HttpMethod.HEAD, url,
        headers: headers, authorization: authorization);

    requestURL = await client._interceptRequest(
        HttpMethod.HEAD, requestURL, requestHeaders);

    return submitHttpRequest(
        client,
        HttpRequest(HttpMethod.HEAD, url, requestURL,
            authorization: authorization,
            queryParameters: queryParameters,
            withCredentials: _withCredentials(client, authorization),
            requestHeaders: requestHeaders),
        progressListener,
        client.logRequests);
  }

  Future<HttpResponse> requestOPTIONS(HttpClient client, String url,
      {Map<String, String>? headers,
      Authorization? authorization,
      Map<String, String?>? queryParameters,
      bool noQueryString = false,
      ProgressListener? progressListener}) async {
    var requestURL = buildRequestURL(client, url,
        authorization: authorization,
        queryParameters: queryParameters,
        noQueryString: noQueryString);

    var requestHeaders = buildRequestHeaders(client, HttpMethod.OPTIONS, url,
        headers: headers, authorization: authorization);

    requestURL = await client._interceptRequest(
        HttpMethod.OPTIONS, requestURL, requestHeaders);

    return submitHttpRequest(
        client,
        HttpRequest(
          HttpMethod.OPTIONS,
          url,
          requestURL,
          authorization: authorization,
          queryParameters: queryParameters,
          withCredentials: _withCredentials(client, authorization),
          requestHeaders: requestHeaders,
        ),
        progressListener,
        client.logRequests);
  }

  Future<HttpResponse> requestPOST(HttpClient client, String url,
      {Map<String, String>? headers,
      Authorization? authorization,
      Map<String, String?>? queryParameters,
      bool noQueryString = false,
      Object? body,
      String? contentType,
      String? accept,
      String? responseType,
      ProgressListener? progressListener}) async {
    var httpBody = HttpRequestBody(body, contentType, queryParameters);
    var requestBody = buildRequestBody(client, httpBody, authorization);

    if (queryParameters != null &&
        queryParameters.isNotEmpty &&
        requestBody.isNull) {
      var requestHeaders = buildRequestHeaders(client, HttpMethod.POST, url,
          headers: headers,
          authorization: authorization,
          contentType: requestBody.contentType,
          accept: accept);

      var formData = buildPOSTFormData(queryParameters, requestHeaders);

      var requestURL = buildRequestURL(client, url,
          authorization: authorization, noQueryString: noQueryString);

      requestURL = await client._interceptRequest(
          HttpMethod.POST, requestURL, requestHeaders);

      return submitHttpRequest(
          client,
          HttpRequest(
            HttpMethod.POST,
            url,
            requestURL,
            authorization: authorization,
            queryParameters: queryParameters,
            withCredentials: _withCredentials(client, authorization),
            requestHeaders: requestHeaders,
            sendData: formData,
            responseType: responseType,
          ),
          progressListener,
          client.logRequests);
    } else {
      var requestHeaders = buildRequestHeaders(client, HttpMethod.POST, url,
          headers: headers,
          authorization: authorization,
          contentType: requestBody.contentType,
          accept: accept);

      var requestURL = buildRequestURL(client, url,
          authorization: authorization,
          queryParameters: queryParameters,
          noQueryString: noQueryString);

      requestURL = await client._interceptRequest(
          HttpMethod.POST, requestURL, requestHeaders);

      return submitHttpRequest(
          client,
          HttpRequest(
            HttpMethod.POST,
            url,
            requestURL,
            authorization: authorization,
            queryParameters: queryParameters,
            withCredentials: _withCredentials(client, authorization),
            requestHeaders: requestHeaders,
            sendData: requestBody.contentAsSendData,
            responseType: responseType,
          ),
          progressListener,
          client.logRequests);
    }
  }

  Future<HttpResponse> requestPUT(HttpClient client, String url,
      {Map<String, String>? headers,
      Authorization? authorization,
      Map<String, String?>? queryParameters,
      bool noQueryString = false,
      Object? body,
      String? contentType,
      String? accept,
      String? responseType,
      ProgressListener? progressListener}) async {
    var httpBody = HttpRequestBody(body, contentType, queryParameters);
    var requestBody = buildRequestBody(client, httpBody, authorization);

    var requestURL = buildRequestURL(client, url,
        authorization: authorization,
        queryParameters: queryParameters,
        noQueryString: noQueryString);

    var requestHeaders = buildRequestHeaders(client, HttpMethod.PUT, url,
        headers: headers,
        authorization: authorization,
        contentType: requestBody.contentType,
        accept: accept);

    requestURL = await client._interceptRequest(
        HttpMethod.PUT, requestURL, requestHeaders);

    return submitHttpRequest(
        client,
        HttpRequest(
          HttpMethod.PUT,
          url,
          requestURL,
          authorization: authorization,
          queryParameters: queryParameters,
          withCredentials: _withCredentials(client, authorization),
          requestHeaders: requestHeaders,
          sendData: requestBody.contentAsSendData,
          responseType: responseType,
        ),
        progressListener,
        client.logRequests);
  }

  Future<HttpResponse> requestPATCH(HttpClient client, String url,
      {Map<String, String>? headers,
      Authorization? authorization,
      Map<String, String?>? queryParameters,
      bool noQueryString = false,
      Object? body,
      String? contentType,
      String? accept,
      String? responseType,
      ProgressListener? progressListener}) async {
    var httpBody = HttpRequestBody(body, contentType, queryParameters);
    var requestBody = buildRequestBody(client, httpBody, authorization);

    if (queryParameters != null &&
        queryParameters.isNotEmpty &&
        requestBody.isNull) {
      var mimeType = MimeType.parse(MimeType.applicationJson);
      var body = HttpBody.from(queryParameters, mimeType);
      httpBody = HttpRequestBody(body, contentType, queryParameters);
      requestBody = buildRequestBody(client, httpBody, authorization);
    }

    var requestURL = buildRequestURL(client, url,
        authorization: authorization,
        queryParameters: queryParameters,
        noQueryString: noQueryString);

    var requestHeaders = buildRequestHeaders(client, HttpMethod.PATCH, url,
        headers: headers,
        authorization: authorization,
        contentType: requestBody.contentType,
        accept: accept);

    requestURL = await client._interceptRequest(
        HttpMethod.PATCH, requestURL, requestHeaders);

    return submitHttpRequest(
        client,
        HttpRequest(
          HttpMethod.PATCH,
          url,
          requestURL,
          authorization: authorization,
          queryParameters: queryParameters,
          withCredentials: _withCredentials(client, authorization),
          requestHeaders: requestHeaders,
          sendData: requestBody.contentAsSendData,
          responseType: responseType,
        ),
        progressListener,
        client.logRequests);
  }

  Future<HttpResponse> requestDELETE(HttpClient client, String url,
      {Map<String, String>? headers,
      Authorization? authorization,
      Map<String, String?>? queryParameters,
      bool noQueryString = false,
      Object? body,
      String? contentType,
      String? accept,
      String? responseType,
      ProgressListener? progressListener}) async {
    var httpBody = HttpRequestBody(body, contentType, queryParameters);
    var requestBody = buildRequestBody(client, httpBody, authorization);

    var requestURL = buildRequestURL(client, url,
        authorization: authorization,
        queryParameters: queryParameters,
        noQueryString: noQueryString);

    var requestHeaders = buildRequestHeaders(client, HttpMethod.DELETE, url,
        headers: headers,
        authorization: authorization,
        contentType: requestBody.contentType,
        accept: accept);

    requestURL = await client._interceptRequest(
        HttpMethod.DELETE, requestURL, requestHeaders);

    return submitHttpRequest(
        client,
        HttpRequest(
          HttpMethod.DELETE,
          url,
          requestURL,
          authorization: authorization,
          queryParameters: queryParameters,
          withCredentials: _withCredentials(client, authorization),
          requestHeaders: requestHeaders,
          sendData: requestBody.contentAsSendData,
          responseType: responseType,
        ),
        progressListener,
        client.logRequests);
  }

  Future<HttpResponse> submitHttpRequest(HttpClient client, HttpRequest request,
      ProgressListener? progressListener, bool log) {
    setupUserAgent(client.userAgent);

    if (!client.hasInterceptor) {
      return doHttpRequest(client, request, progressListener, log);
    }

    return doHttpRequest(client, request, progressListener, log)
        .then((response) => client._interceptResponse(response));
  }

  /// Implements teh actual HTTP request for imported platform.
  Future<HttpResponse> doHttpRequest(HttpClient client, HttpRequest request,
      ProgressListener? progressListener, bool log);

  String buildPOSTFormData(Map<String, String?> data,
      [Map<String, String>? requestHeaders]) {
    var formData = buildQueryString(data);

    if (requestHeaders != null) {
      requestHeaders.putIfAbsent(HttpRequest._headerKeyContentType,
          () => 'application/x-www-form-urlencoded; charset=UTF-8');
    }

    return formData;
  }

  /// Helper to build a Query String.
  String buildQueryString(Map<String, String?>? data) {
    if (data == null || data.isEmpty) return '';

    var query = StringBuffer();

    data.forEach((key, value) {
      var keyEncoded = Uri.encodeQueryComponent(key);
      var valueEncoded = value != null ? Uri.encodeQueryComponent(value) : '';
      var keyValue = '$keyEncoded=$valueEncoded';

      if (query.isNotEmpty) {
        query.write('&');
      }
      query.write(keyValue);
    });

    return query.toString();
  }

  /// Helper to build the request headers.
  Map<String, String> buildRequestHeaders(
    HttpClient client,
    HttpMethod method,
    String url, {
    Map<String, String>? headers,
    Authorization? authorization,
    String? contentType,
    String? accept,
  }) {
    var requestHeaders = client.buildRequestHeaders(url) ?? <String, String>{};

    if (contentType != null && method != HttpMethod.GET) {
      requestHeaders[HttpRequest._headerKeyContentType] = contentType;
    }

    if (accept != null) {
      requestHeaders['Accept'] = accept;
    }

    if (authorization != null && authorization.usesAuthorizationHeader) {
      var credential = authorization.resolvedCredential!;
      var authorizationHeaderLine = credential.buildAuthorizationHeaderLine();
      if (authorizationHeaderLine != null) {
        requestHeaders['Authorization'] = authorizationHeaderLine;
      }
    }

    if (headers != null) {
      requestHeaders.addAll(headers);
    }

    return requestHeaders;
  }

  /// Helper to build the request URL.
  String buildRequestURL(HttpClient client, String url,
      {Authorization? authorization,
      Map<String, String?>? queryParameters,
      bool noQueryString = false}) {
    if (queryParameters != null && queryParameters.isNotEmpty) {
      url = buildURLWithQueryParameters(url, queryParameters,
          removeFragment: true);
    }

    if (authorization != null && authorization.isCredentialResolved) {
      var authorizationURL = authorization.resolvedCredential!.buildURL(url);
      if (authorizationURL != null) return authorizationURL;
    }

    if (noQueryString) {
      url = removeUriQueryString(url).toString();
    }

    return url;
  }

  /// Helper to build the request body.
  HttpRequestBody buildRequestBody(HttpClient client, HttpRequestBody httpBody,
      Authorization? authorization) {
    if (authorization != null && authorization.isCredentialResolved) {
      var jsonBody = authorization.resolvedCredential!.buildBody(httpBody);
      if (jsonBody != null) return jsonBody;
    }

    return httpBody;
  }

  /// Closes the [HttpClientRequester] and internal instances.
  void close() {}
}

typedef HttpClientURLFilter = String Function(
    String url, Map<String, String?>? queryParameters);

typedef AuthorizationInterceptor = void Function(Authorization? authorization);

/// Represents a simple HTTP call that can be called many times.
class HttpCall<R> {
  final HttpClient client;
  final HttpMethod method;
  final String path;
  final bool fullPath;
  final Object? body;
  final int maxRetries;

  HttpCall(
      {String? baseURL,
      HttpClient? client,
      this.method = HttpMethod.GET,
      this.path = '',
      this.fullPath = false,
      this.body,
      this.maxRetries = 0})
      : client = client ?? HttpClient(baseURL ?? getUriBase().toString());

  /// Performs a call, making the HTTP request.
  Future<HttpResponse?> call(Map<String, dynamic>? parameters,
      {Object? body, int? maxRetries}) async {
    maxRetries ??= this.maxRetries;

    var limit = Math.max(1, 1 + maxRetries);

    HttpResponse? response;

    for (var i = 0; i < limit; i++) {
      response = await _doRequestImp(parameters, body);
      if (response.isOK) {
        return response;
      }
    }

    return response;
  }

  /// Performs a call, making the HTTP request, than resolves the response.
  Future<R?> callAndResolve(Map<String, dynamic>? parameters,
      {Object? body, int? maxRetries}) async {
    var response = (await call(parameters, body: body, maxRetries: maxRetries));
    return resolveResponse(response);
  }

  Future<HttpResponse> _doRequestImp(
      Map<String, dynamic>? parameters, Object? body) async {
    if (canHttpMethodHaveBody(method)) {
      body ??= this.body;
    } else {
      body = null;
    }

    var response = await requestHttpClient(
        client, method, path, fullPath, parameters, body);
    return response;
  }

  static Map<String, String>? toQueryParameters(Map? parameters) {
    if (parameters == null) return null;

    if (parameters is Map<String, String>) {
      return parameters;
    }

    var queryParameters = parameters
        .map((key, value) => MapEntry('$key', toQueryParameterValue(value)));
    return queryParameters;
  }

  static String toQueryParameterValue(Object? value) {
    if (value == null) return '';
    if (value is List) return value.join(',');
    if (value is Map) {
      return value.entries.map((e) => '${e.key}:${e.value}').join(',');
    }
    return '$value';
  }

  /// Method responsible to request the [HttpClient].
  ///
  /// Can be overwritten by other implementations.
  Future<HttpResponse> requestHttpClient(HttpClient client, HttpMethod method,
      String path, bool fullPath, Map? parameters, Object? body) {
    var queryParameters = toQueryParameters(parameters);
    return client.request(method, path,
        fullPath: fullPath, parameters: queryParameters, body: body);
  }

  /// Method responsible to resolve the [response] to a [R] value.
  ///
  /// Can be overwritten by other implementations.
  R? resolveResponse(HttpResponse? response) {
    if (response == null) {
      return null;
    } else if (!response.isOK) {
      throw StateError(
          "Can't perform request. Response{ status: ${response.status} ; body: ${response.bodyAsString}} > $this");
    } else if (response.isBodyTypeJSON) {
      return response.json as R?;
    } else {
      return response.bodyAsString as R?;
    }
  }

  @override
  String toString() {
    return 'HttpCall{client: $client, method: $method, path: $path, fullPath: $fullPath, body: $body, maxRetries: $maxRetries}';
  }
}

/// Mercury HTTP Client.
class HttpClient {
  /// The base URL for the client requests.
  late String baseURL;

  /// Requester implementation.
  late HttpClientRequester _clientRequester;

  /// Returns the [HttpClientRequester] instance.
  HttpClientRequester get clientRequester => _clientRequester;

  static int _idCounter = 0;

  /// ID of this client.
  final int id = ++_idCounter;

  /// The JSON decoder. Default: `dart:convert json`
  dynamic Function(String jsonEncoded)? jsonDecoder;

  String? userAgent;

  HttpClient(String baseURL, [HttpClientRequester? clientRequester]) {
    var baseURL2 = baseURL.trimLeft();

    if (baseURL2.endsWith('/')) {
      baseURL2 = baseURL2.substring(0, baseURL2.length - 1);
    }

    if (baseURL2.isEmpty) {
      throw ArgumentError('Invalid baseURL');
    }

    this.baseURL = baseURL2;

    _clientRequester = clientRequester ?? createHttpClientRequester();
  }

  /// Returns a new [HttpClient] instance using [baseURL].
  ///
  /// [preserveAuthorization] if [true] will keep the same [authorization] instance.
  /// NOTE: If the current instance is using the same [baseURL], [this] instance is returned.
  HttpClient withBaseURL(String baseURL, {bool preserveAuthorization = false}) {
    if (this.baseURL == baseURL) {
      return this;
    }
    var httpClient = HttpClient(baseURL, clientRequester)
      ..userAgent = userAgent;

    if (preserveAuthorization) {
      httpClient._authorization = _authorization;
    }

    return httpClient;
  }

  /// Returns a new [HttpClient] instance using [basePath] as path of [baseURL].
  HttpClient withBasePath(String basePath) {
    var uri = Uri.parse(baseURL);

    var uri2 = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: (uri.port != 80 && uri.port != 443) ? uri.port : null,
      path: basePath,
      query: uri.hasQuery ? uri.query : null,
      userInfo: isNotEmptyString(uri.userInfo) ? uri.userInfo : null,
    );

    return withBaseURL(uri2.toString());
  }

  /// The URL filter, if present.
  HttpClientURLFilter? urlFilter;

  @override
  String toString() {
    return 'HttpClient{ '
        'id: $id, '
        'baseURL: $baseURL, '
        'authorization: $authorization, '
        'crossSiteWithCredentials: $crossSiteWithCredentials, '
        'logJSON: $logJSON, '
        'clientRequester: $_clientRequester '
        '}';
  }

  /// Returns [true] if this [baseURL] is `localhost`.
  bool isBaseUrlLocalhost() {
    var uri = Uri.parse(baseURL);
    return isLocalhost(uri.host);
  }

  /// Requests using [method] and [path] and returns a decoded JSON.
  Future<dynamic> requestJSON(HttpMethod method, String path,
      {Map<String, String>? headers,
      Credential? authorization,
      Map<String, Object?>? queryParameters,
      Object? body,
      String? contentType,
      String? accept}) async {
    return request(method, path,
            headers: headers,
            authorization: authorization,
            parameters: queryParameters,
            body: body,
            contentType: contentType,
            accept: accept)
        .then((r) => _jsonDecodeResponse(r));
  }

  /// Does a GET request and returns a decoded JSON.
  Future<dynamic> getJSON(String path,
      {Map<String, String>? headers,
      Credential? authorization,
      Map<String, Object?>? parameters}) async {
    return get(path,
            headers: headers,
            authorization: authorization,
            parameters: parameters)
        .then((r) => _jsonDecodeResponse(r));
  }

  /// Does an OPTION request and returns a decoded JSON.
  Future<dynamic> optionsJSON(String path,
      {Map<String, String>? headers,
      Credential? authorization,
      Map<String, Object?>? parameters}) async {
    return options(path,
            headers: headers,
            authorization: authorization,
            parameters: parameters)
        .then((r) => _jsonDecodeResponse(r));
  }

  /// Does a POST request and returns a decoded JSON.
  Future<dynamic> postJSON(String path,
      {Map<String, String>? headers,
      Credential? authorization,
      Map<String, Object?>? parameters,
      Object? body,
      String? contentType}) async {
    return post(path,
            headers: headers,
            authorization: authorization,
            parameters: parameters,
            body: body,
            contentType: contentType)
        .then((r) => _jsonDecodeResponse(r));
  }

  /// Does a PUT request and returns a decoded JSON.
  Future<dynamic> putJSON(String path,
      {Map<String, String>? headers,
      Credential? authorization,
      Object? body,
      String? contentType}) async {
    return put(path,
            headers: headers,
            authorization: authorization,
            body: body,
            contentType: contentType)
        .then((r) => _jsonDecodeResponse(r));
  }

  /// If set to true, sends credential to cross sites.
  bool? crossSiteWithCredentials;

  Authorization? _authorization;

  /// The [Authorization] (that resolves [Credential]) for requests.
  Authorization? get authorization => _authorization;

  set authorization(Authorization? authorization) {
    _authorization = authorization;
    _notifyResolvedAuthorization();
  }

  void _notifyResolvedAuthorization() {
    if (_authorization != null &&
        authorizationResolutionInterceptor != null &&
        _authorization!.isCredentialResolved) {
      try {
        authorizationResolutionInterceptor!(_authorization);
      } catch (e, s) {
        print(e);
        print(s);
      }
    }
  }

  AuthorizationInterceptor? authorizationResolutionInterceptor;

  String? _responseHeaderWithToken;

  /// The response header with a token to use as [authorization] [Credential].
  String? get responseHeaderWithToken => _responseHeaderWithToken;

  /// If set, will automatically use a token in the
  /// header [responseHeaderWithToken], when found in any request.
  HttpClient autoChangeAuthorizationToBearerToken(
      String responseHeaderWithToken) {
    _responseHeaderWithToken = responseHeaderWithToken;
    return this;
  }

  bool logRequests = false;

  bool logJSON = false;

  dynamic _jsonDecodeResponse(HttpResponse r) {
    if (r.isStatusNetworkError || r.isStatusServerError) {
      var error = r.error;
      if (error != null) {
        throw error;
      }

      var status = r.status;
      var errorMessage =
          "Can't parse JSON from an HTTP $status error response.";

      var httpError =
          HttpError(r.url, r.url, status, errorMessage, errorMessage);
      throw httpError;
    }

    String? body;

    try {
      body = r.bodyAsString;
      return _jsonDecode(body);
    } catch (e, s) {
      Object? source;
      int? offset;

      if (e is FormatException) {
        source = e.source;
        offset = e.offset;
      }

      Error.throwWithStackTrace(
          FormatException(
              "JSON parsing error:\n-- Request: $r\n-- Cause: $e\n$body",
              source,
              offset),
          s);
    }
  }

  dynamic _jsonDecode(String? s) {
    if (logJSON) _logJSON(s);

    if (s == null || s.isEmpty) return null;

    var jsonDecoder = this.jsonDecoder;

    if (jsonDecoder != null) {
      return jsonDecoder(s);
    } else {
      return jsonDecode(s);
    }
  }

  void _logJSON(String? json) {
    var now = DateTime.now();
    print('$now> HttpClient> $json');
  }

  Future<Authorization?> _buildRequestAuthorization(
      Credential? credential) async {
    if (credential != null) {
      return Authorization.fromCredential(credential);
    }

    return _resolveAuthorization();
  }

  /// Returns [true] if [authorization] is resolved.
  bool get isAuthorizationResolved =>
      authorization != null && authorization!.isCredentialResolved;

  /// Returns the [authorization] if is resolved.
  Authorization? get resolvedAuthorization =>
      isAuthorizationResolved ? authorization : null;

  Future<Authorization?> _resolveAuthorization() async {
    if (_authorization == null) return Future.value(null);

    if (_authorization!.isResolvingCredential) {
      print('WARNING: '
          'Authorization[${_authorization.runtimeType}] is already resolving a credential! '
          '(NOTE: Do not use this client instance for network resolution while resolving a Credential)');
    }

    await _authorization!.resolveCredential(this, null);
    _notifyResolvedAuthorization();
    return _authorization;
  }

  /// Does a request using [method].
  Future<HttpResponse> request(HttpMethod method, String path,
      {bool fullPath = false,
      Map<String, String>? headers,
      Credential? authorization,
      Map<String, Object?>? parameters,
      String? queryString,
      Object? body,
      String? contentType,
      String? accept,
      bool noQueryString = false,
      ProgressListener? progressListener}) async {
    var parametersMapStr = _toParametersMapOfString(parameters);
    var url = buildMethodRequestURL(method, path, fullPath, parametersMapStr);

    var retUrlParameters =
        _buildURLAndParameters(url, parametersMapStr, queryString);
    url = retUrlParameters.key;
    parametersMapStr = retUrlParameters.value;

    return requestURL(method, url,
        headers: headers,
        authorization: authorization,
        queryParameters: parametersMapStr,
        body: body,
        contentType: contentType,
        accept: accept,
        noQueryString: noQueryString,
        progressListener: progressListener);
  }

  /// Builds the URL for [method] using [path] or [fullPath].
  String buildMethodRequestURL(HttpMethod method, String? path, bool fullPath,
          Map<String, String?>? parameters) =>
      _buildURL(path, fullPath, parameters, methodAcceptsQueryString(method));

  Future<HttpResponse> requestURL(HttpMethod method, String url,
      {Map<String, String>? headers,
      Credential? authorization,
      Map<String, Object?>? queryParameters,
      noQueryString = false,
      Object? body,
      String? contentType,
      String? accept,
      ProgressListener? progressListener}) async {
    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.request(this, method, url,
        headers: headers,
        authorization: requestAuthorization,
        queryParameters: _toParametersMapOfString(queryParameters),
        noQueryString: noQueryString,
        body: body,
        contentType: contentType,
        accept: accept,
        progressListener: progressListener);
  }

  //////////////

  /// Does a GET request.
  Future<HttpResponse> get(String path,
      {Map<String, String>? headers,
      bool fullPath = false,
      Credential? authorization,
      Map<String, Object?>? parameters,
      String? accept,
      String? responseType,
      ProgressListener? progressListener}) async {
    var parametersMapStr = _toParametersMapOfString(parameters);
    var url = _buildURL(path, fullPath, parametersMapStr, true);
    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestGET(this, url,
        headers: headers,
        authorization: requestAuthorization,
        accept: accept,
        responseType: responseType,
        progressListener: progressListener);
  }

  /// Does a HEAD request.
  Future<HttpResponse> head(String path,
      {Map<String, String>? headers,
      bool fullPath = false,
      Credential? authorization,
      Map<String, Object?>? parameters,
      ProgressListener? progressListener}) async {
    var parametersMapStr = _toParametersMapOfString(parameters);
    var url = _buildURL(path, fullPath, parametersMapStr, true);
    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestHEAD(this, url,
        headers: headers,
        authorization: requestAuthorization,
        progressListener: progressListener);
  }

  /// Does an OPTIONS request.
  Future<HttpResponse> options(String path,
      {Map<String, String>? headers,
      bool fullPath = false,
      Credential? authorization,
      Map<String, Object?>? parameters,
      ProgressListener? progressListener}) async {
    var parametersMapStr = _toParametersMapOfString(parameters);
    var url = _buildURL(path, fullPath, parametersMapStr, true);
    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestOPTIONS(this, url,
        headers: headers,
        authorization: requestAuthorization,
        progressListener: progressListener);
  }

  /// Does a POST request.
  Future<HttpResponse> post(String path,
      {Map<String, String>? headers,
      bool fullPath = false,
      Credential? authorization,
      Map<String, Object?>? parameters,
      String? queryString,
      Object? body,
      String? contentType,
      String? accept,
      String? responseType,
      ProgressListener? progressListener}) async {
    var parametersMapStr = _toParametersMapOfString(parameters);
    var url = _buildURL(path, fullPath, parametersMapStr);

    var retUrlParameters =
        _buildURLAndParameters(url, parametersMapStr, queryString);
    url = retUrlParameters.key;
    parametersMapStr = retUrlParameters.value;

    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestPOST(this, url,
        headers: headers,
        authorization: requestAuthorization,
        queryParameters: parametersMapStr,
        body: body,
        contentType: contentType,
        accept: accept,
        responseType: responseType,
        progressListener: progressListener);
  }

  /// Does a PUT request.
  Future<HttpResponse> put(String path,
      {Map<String, String>? headers,
      bool fullPath = false,
      Credential? authorization,
      Map<String, Object?>? parameters,
      String? queryString,
      Object? body,
      String? contentType,
      String? accept,
      String? responseType,
      ProgressListener? progressListener}) async {
    var parametersMapStr = _toParametersMapOfString(parameters);
    var url = _buildURL(path, fullPath, parametersMapStr);

    var retUrlParameters =
        _buildURLAndParameters(url, parametersMapStr, queryString);
    url = retUrlParameters.key;
    parametersMapStr = retUrlParameters.value;

    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestPUT(this, url,
        headers: headers,
        authorization: requestAuthorization,
        queryParameters: parametersMapStr,
        body: body,
        contentType: contentType,
        accept: accept,
        responseType: responseType,
        progressListener: progressListener);
  }

  /// Does a PATCH request.
  Future<HttpResponse> patch(String path,
      {Map<String, String>? headers,
      bool fullPath = false,
      Credential? authorization,
      Map<String, Object?>? parameters,
      String? queryString,
      Object? body,
      String? contentType,
      String? accept,
      String? responseType,
      ProgressListener? progressListener}) async {
    var parametersMapStr = _toParametersMapOfString(parameters);
    var url = _buildURL(path, fullPath, parametersMapStr);

    var retUrlParameters =
        _buildURLAndParameters(url, parametersMapStr, queryString);
    url = retUrlParameters.key;
    parametersMapStr = retUrlParameters.value;

    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestPATCH(this, url,
        headers: headers,
        authorization: requestAuthorization,
        queryParameters: parametersMapStr,
        body: body,
        contentType: contentType,
        accept: accept,
        responseType: responseType,
        progressListener: progressListener);
  }

  /// Does a DELETE request.
  Future<HttpResponse> delete(String path,
      {Map<String, String>? headers,
      bool fullPath = false,
      Credential? authorization,
      Map<String, String?>? parameters,
      String? queryString,
      Object? body,
      String? contentType,
      String? accept,
      String? responseType,
      ProgressListener? progressListener}) async {
    var url = _buildURL(path, fullPath, parameters);

    var retUrlParameters = _buildURLAndParameters(url, parameters, queryString);
    url = retUrlParameters.key;
    parameters = retUrlParameters.value;

    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestDELETE(this, url,
        headers: headers,
        authorization: requestAuthorization,
        queryParameters: parameters,
        body: body,
        contentType: contentType,
        accept: accept,
        responseType: responseType,
        progressListener: progressListener);
  }

  //////////////

  Uri _removeURIQueryParameters(Uri uri) {
    if (uri.scheme.toLowerCase() == 'https') {
      return Uri.https(uri.authority, Uri.decodeComponent(uri.path));
    } else {
      return Uri.http(uri.authority, Uri.decodeComponent(uri.path));
    }
  }

  Uri _setURIQueryString(Uri uri, String? queryString) {
    int? port = uri.port;

    if (uri.scheme == 'https' && uri.port == 443) {
      port = null;
    } else if (uri.scheme == 'http' && uri.port == 80) {
      port = null;
    }

    return Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo,
        host: uri.host,
        port: port,
        path: Uri.decodeComponent(uri.path),
        query: queryString);
  }

  MapEntry<String, Map<String, String?>?> _buildURLAndParameters(
      String url, Map<String, String?>? parameters, String? queryString) {
    var uri = Uri.parse(url);

    if (uri.queryParameters.isNotEmpty) {
      if (parameters != null && parameters.isNotEmpty) {
        uri.queryParameters
            .forEach((k, v) => parameters!.putIfAbsent(k, () => v));
      } else {
        parameters = uri.queryParameters;
      }

      url = _removeURIQueryParameters(uri).toString();
      uri = Uri.parse(url);
    }

    if (isNotEmptyString(queryString)) {
      if (queryString!.contains('{{')) {
        queryString = buildStringPattern(queryString, parameters ?? {});
      }

      uri = _setURIQueryString(uri, queryString);
      url = uri.toString();

      parameters = null;
    }

    return MapEntry(url, parameters);
  }

  /// Builds a Request URL, with the same rules of [requestURL].
  String buildRequestURL(HttpMethod method, String path,
      {bool fullPath = false,
      Authorization? authorization,
      Map<String, Object?>? parameters,
      String? queryString,
      bool noQueryString = false}) {
    var parametersMapStr = _toParametersMapOfString(parameters);
    var url = buildMethodRequestURL(method, path, fullPath, parametersMapStr);

    var retUrlParameters =
        _buildURLAndParameters(url, parametersMapStr, queryString);
    url = retUrlParameters.key;
    parametersMapStr = retUrlParameters.value;

    return _clientRequester.buildRequestURL(this, url,
        authorization: authorization,
        queryParameters: parametersMapStr,
        noQueryString: noQueryString);
  }

  /// Builds a URL, using [baseURL] with [path] or [fullPath].
  String buildURL(String path, bool fullPath,
      [Map<String, String?>? queryParameters,
      bool allowURLQueryString = true]) {
    return _buildURL(path, fullPath, queryParameters, allowURLQueryString);
  }

  String _buildURL(
      String? path, bool fullPath, Map<String, String?>? parameters,
      [bool allowURLQueryString = false]) {
    var queryParameters = allowURLQueryString ? parameters : null;

    if (path == null) {
      if (queryParameters == null || queryParameters.isEmpty) {
        return baseURL;
      } else {
        return _buildURLWithParameters(baseURL, queryParameters);
      }
    }

    if (path.contains('{{')) {
      path = buildStringPattern(path, parameters ?? {})!;
    }

    if (!path.startsWith('/')) path = '/$path';

    String url;

    if (fullPath) {
      var uri = Uri.parse(baseURL);

      Uri uri2;
      if (uri.scheme.toLowerCase() == 'https') {
        uri2 = Uri.https(uri.authority, path);
      } else {
        uri2 = Uri.http(uri.authority, path);
      }

      url = uri2.toString();
    } else {
      url = '$baseURL$path';
    }

    if (urlFilter != null) {
      var url2 = urlFilter!(url, queryParameters);
      if (url2.isNotEmpty && url2 != url) {
        url = url2;
      }
    }

    return _buildURLWithParameters(url, queryParameters);
  }

  String _buildURLWithParameters(
      String url, Map<String, String?>? queryParameters) {
    var uri = Uri.parse(url);

    var uriParameters = uri.queryParameters;

    if (uriParameters.isNotEmpty) {
      if (queryParameters == null || queryParameters.isEmpty) {
        queryParameters = uriParameters;
      } else {
        for (var e in uriParameters.entries) {
          queryParameters.putIfAbsent(e.key, () => e.value);
        }
      }
    }

    if (queryParameters != null && queryParameters.isEmpty) {
      queryParameters = null;
    }

    Uri uri2;

    if (uri.scheme.toLowerCase() == 'https') {
      uri2 = Uri.https(
          uri.authority, Uri.decodeComponent(uri.path), queryParameters);
    } else {
      uri2 = Uri.http(
          uri.authority, Uri.decodeComponent(uri.path), queryParameters);
    }

    var url2 = uri2.toString();

    return url2;
  }

  /// Function that processes any request response.
  ResponseProcessor? responseProcessor;

  /// Builds initial headers for each request.
  RequestHeadersBuilder? requestHeadersBuilder;

  Map<String, String>? buildRequestHeaders(String url) {
    if (requestHeadersBuilder == null) return null;
    return requestHeadersBuilder!(this, url);
  }

  /// An optional interceptor, that can be used to log requests or to change
  /// headers and URLs.
  HttpClientInterceptor? interceptor;

  /// Returns `true` if has an [interceptor].
  bool get hasInterceptor => interceptor != null;

  FutureOr<String> _interceptRequest(
      HttpMethod method, String url, Map<String, String> headers) {
    var interceptor = this.interceptor;
    if (interceptor != null) {
      var ret = interceptor.filterRequest(this, method, url, headers);
      if (ret is Future<String?>) {
        return ret.then((url2) => url2 != null && url2.isNotEmpty ? url2 : url);
      } else {
        return ret != null && ret.isNotEmpty ? ret : url;
      }
    } else {
      return url;
    }
  }

  FutureOr<HttpResponse> _interceptResponse(HttpResponse response) {
    var interceptor = this.interceptor;
    if (interceptor != null) {
      var ret = interceptor.filterResponse(this, response);
      if (ret is Future<HttpResponse?>) {
        return ret.then((response2) => response2 ?? response);
      } else {
        return ret ?? response;
      }
    } else {
      return response;
    }
  }
}

/// An interceptor that can be used to filter requests and responses.
abstract class HttpClientInterceptor {
  /// Filters the request before submit.
  ///
  /// Any modification to [headers] will be submitted.
  /// - [client] the [HttpClient] performing the request.
  /// - [method] the HTTP Method of the request.
  /// - [url] the request URL.
  /// - [headers] the headers of the request that can be modified.
  /// - Return: should return the URL. If `null` or empty is returned the original [url] will be used.
  FutureOr<String?> filterRequest(HttpClient client, HttpMethod method,
          String url, Map<String, String>? headers) =>
      null;

  /// Filters the [response] before is returned by the [client].
  ///
  /// - Return: should return a filtered [HttpResponse] or `null` if no filter is performed.
  FutureOr<HttpResponse?> filterResponse(
          HttpClient client, HttpResponse response) =>
      null;
}

typedef SimulateResponse = dynamic Function(
    String url, Map<String, String?>? queryParameters);

/// A Simulated [HttpClientRequester]. Useful for tests and mocks.
class HttpClientRequesterSimulation extends HttpClientRequester {
  @override
  bool setupUserAgent(String? userAgent) => false;

  final Map<RegExp, SimulateResponse> _getPatterns = {};

  /// Defines a reply [response] for GET requests with [urlPattern].
  void replyGET(RegExp urlPattern, String response) {
    simulateGET(urlPattern, (u, p) => response);
  }

  /// Defines GET simulated [response] for [urlPattern].
  void simulateGET(RegExp urlPattern, SimulateResponse response) {
    _getPatterns[urlPattern] = response;
  }

  final Map<RegExp, SimulateResponse> _optionsPatterns = {};

  /// Defines a reply [response] for OPTIONS requests with [urlPattern].
  void replyOPTIONS(RegExp urlPattern, String response) {
    simulateOPTIONS(urlPattern, (u, p) => response);
  }

  /// Defines OPTIONS simulated [response] for [urlPattern].
  void simulateOPTIONS(RegExp urlPattern, SimulateResponse response) {
    _optionsPatterns[urlPattern] = response;
  }

  final Map<RegExp, SimulateResponse> _postPatterns = {};

  /// Defines a reply [response] for POST requests with [urlPattern].
  void replyPOST(RegExp urlPattern, String response) {
    simulatePOST(urlPattern, (u, p) => response);
  }

  /// Defines POST simulated [response] for [urlPattern].
  void simulatePOST(RegExp urlPattern, SimulateResponse response) {
    _postPatterns[urlPattern] = response;
  }

  final Map<RegExp, SimulateResponse> _putPatterns = {};

  /// Defines a reply [response] for PUT requests with [urlPattern].
  void replyPUT(RegExp urlPattern, String response) {
    simulatePUT(urlPattern, (u, p) => response);
  }

  /// Defines PUT simulated [response] for [urlPattern].
  void simulatePUT(RegExp urlPattern, SimulateResponse response) {
    _putPatterns[urlPattern] = response;
  }

  final Map<RegExp, SimulateResponse> _anyPatterns = {};

  /// Defines a reply [response] for any Method requests with [urlPattern].
  void replyANY(RegExp urlPattern, String response) {
    simulateANY(urlPattern, (u, p) => response);
  }

  /// Defines simulated [response] for [urlPattern] for any Method.
  void simulateANY(RegExp urlPattern, SimulateResponse response) {
    _anyPatterns[urlPattern] = response;
  }

  ////////////

  /// Returns for parameter [method] a [Map] with [RegExp] patterns as key and [SimulateResponse] as value.
  Map<RegExp, SimulateResponse> getSimulationPatternsByMethod(
      HttpMethod method) {
    switch (method) {
      case HttpMethod.GET:
        return _getPatterns;
      case HttpMethod.OPTIONS:
        return _optionsPatterns;
      case HttpMethod.PUT:
        return _putPatterns;
      case HttpMethod.POST:
        return _postPatterns;
      default:
        return _anyPatterns;
    }
  }

  SimulateResponse? _findResponse(
      String url, Map<RegExp, SimulateResponse> patterns) {
    if (patterns.isEmpty) return null;

    for (var p in patterns.keys) {
      if (p.hasMatch(url)) {
        return patterns[p];
      }
    }
    return null;
  }

  /// Implementation for simulated requests.
  @override
  Future<HttpResponse> doHttpRequest(HttpClient client, HttpRequest request,
      ProgressListener? progressListener, bool log) {
    var methodPatterns = getSimulationPatternsByMethod(request.method);
    return _requestSimulated(client, request.method, request.requestURL,
        methodPatterns, request.queryParameters);
  }

  Future<HttpResponse> _requestSimulated(
      HttpClient client,
      HttpMethod method,
      String url,
      Map<RegExp, SimulateResponse> methodPatterns,
      Map<String, String?>? queryParameters) {
    var resp =
        _findResponse(url, methodPatterns) ?? _findResponse(url, _anyPatterns);

    if (resp == null) {
      return Future.error('No simulated response[$method]');
    }

    var respVal = resp(url, queryParameters);

    var restResponse = HttpResponse(
        method, url, url, 200, HttpBody.from(respVal),
        jsonDecoder: client.jsonDecoder);

    return Future.value(restResponse);
  }
}

/// Returns de decoder for a Content-Type at parameter [mimeType] and [charset].
Converter<List<int>, String> contentTypeToDecoder(MimeType mimeType) {
  if (mimeType.isJSON || mimeType.isCharsetUTF8) {
    return utf8.decoder;
  } else if (mimeType.isFormURLEncoded || mimeType.isCharsetLATIN1) {
    return latin1.decoder;
  } else {
    return latin1.decoder;
  }
}

/// Creates a HttpClientRequester based in imported platform.
HttpClientRequester createHttpClientRequester() {
  return createHttpClientRequesterImpl();
}

/// Returns the base runtime Uri for the platform.
Uri getHttpClientRuntimeUri() {
  return getHttpClientRuntimeUriImpl();
}

Map<String, String?>? _toParametersMapOfString(
    Map<String, Object?>? parameters) {
  if (parameters == null) return null;
  if (parameters is Map<String, String?>) return parameters;
  return Map<String, String?>.fromEntries(
      parameters.entries.map((e) => MapEntry(e.key, e.value?.toString())));
}

V? _getMapValueKeyIgnoreCase<V>(Map<String, V>? map, String key) {
  if (map == null || map.isEmpty) return null;
  var k = _getMapKeyIgnoreCase(map, key);
  return k != null ? map[k] : null;
}

String? _getMapKeyIgnoreCase(Map<String, Object?>? map, String key) {
  if (map == null || map.isEmpty) return null;

  if (map.containsKey(key)) {
    return key;
  }

  var keyLC = key.toLowerCase();

  if (map.containsKey(keyLC)) {
    return keyLC;
  }

  for (var k in map.keys) {
    if (equalsIgnoreAsciiCase(k, key)) {
      return k;
    }
  }

  return null;
}
