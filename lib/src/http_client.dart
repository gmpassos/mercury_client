import 'dart:async';
import 'dart:convert';

import 'package:enum_to_string/enum_to_string.dart';
import 'package:swiss_knife/swiss_knife.dart';

import 'http_client_none.dart'
    if (dart.library.html) 'http_client_browser.dart'
    if (dart.library.io) 'http_client_io.dart';

typedef ResponseHeaderGetter = String Function(String headerKey);

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

  /// Returns [true] if is 404 status (Not Found).
  bool get isStatusNotFound => isStatus(404);

  /// Returns [true] if is 401 status (Unauthenticated).
  bool get isStatusUnauthenticated => isStatus(401);

  /// Returns [true] if is 403 status (Forbidden).
  bool get isStatusForbidden => isStatus(403);

  /// Returns [true] if any network error happens.
  bool get isStatusNetworkError => status == null || status <= 0;

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
    return this.status != null && this.status == status;
  }

  /// Returns [true] if this status is in range of parameters [statusInit] and [statusEnd].
  bool isStatusInRange(int statusInit, int statusEnd) {
    return status != null && status >= statusInit && status <= statusEnd;
  }

  /// Returns [true] if this status is in [statusList].
  bool isStatusInList(List<int> statusList) {
    return status != null &&
        (statusList.firstWhere((id) => id == status, orElse: () => null) !=
            null);
  }
}

/// Represents a response Error.
class HttpError extends HttpStatus {
  /// The error message, for better understanding than [error].
  final String message;

  /// The actual error thrown by the client.
  final dynamic error;

  HttpError(
      String url, String requestedURL, int status, this.message, this.error)
      : super(url, requestedURL, status);

  /// If has the field [message]
  bool get hasMessage => message != null && message.isNotEmpty;

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
    if (key == null ||
        values == null ||
        key.isEmpty ||
        values.isEmpty ||
        !hasMessage) return false;

    for (var value in values) {
      if (matchesJSONEntry(key, value, text)) return true;
    }

    return false;
  }

  bool matchesJSONEntry(String key, String value, bool text) {
    if (hasMessage && message.contains(key) && message.contains(value)) {
      var entryValue = text ? '"$value"' : '$value';
      return RegExp('"$key":\\s*$entryValue').hasMatch(message);
    }
    return false;
  }

  @override
  String toString() {
    return 'RESTError{requestedURL: $requestedURL, status: $status, message: $message, error: $error}';
  }
}

/// The response of a [HttpRequest].
class HttpResponse extends HttpStatus implements Comparable<HttpResponse> {
  /// Response Method
  final HttpMethod method;

  /// Response body.
  final String body;

  /// A getter capable to get a header entry value.
  final ResponseHeaderGetter _responseHeaderGetter;

  /// Actual request of the client.
  final dynamic request;

  /// Time of instantiation.
  final int instanceTime = DateTime.now().millisecondsSinceEpoch;

  int _accessTime;

  HttpResponse(
      this.method, String url, String requestedURL, int status, this.body,
      [this._responseHeaderGetter, this.request])
      : super(url, requestedURL, status) {
    _accessTime = instanceTime;
  }

  /// Last access time of this request. Used for caches timeout.
  int get accessTime => _accessTime;

  void updateAccessTime() {
    _accessTime = DateTime.now().millisecondsSinceEpoch;
  }

  /// Tries to determine the memory usage of this response.
  int memorySize() {
    var memory = 1 +
        8 +
        8 +
        (method != null ? 4 : 0) +
        (body != null ? body.length : 0) +
        (url == requestedURL ? url.length : url.length + requestedURL.length);
    return memory;
  }

  /// Returns the [body] as JSON.
  dynamic get json => hasBody ? jsonDecode(body) : null;

  /// Returns [true] if has [body].
  bool get hasBody => body != null && body.isNotEmpty;

  /// The [body] type (Content-Type).
  String get bodyType => getResponseHeader('Content-Type');

  /// Same as [bodyType], but returns as [MimeType].
  MimeType get bodyMimeType {
    return MimeType.parse(bodyType);
  }

  /// Returns [true] if [bodyType] is a JSON (application/json).
  bool get isBodyTypeJSON {
    var mimeType = bodyMimeType;
    if (mimeType == null) return false;
    return mimeType.isJSON || mimeType.isJavascript;
  }

  /// Returns [body] as a [JSONPaging].
  JSONPaging get asJSONPaging {
    if (isBodyTypeJSON) {
      return JSONPaging.from(json);
    }
    return null;
  }

  /// Returns the header value for the parameter [headerKey].
  String getResponseHeader(String headerKey) {
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
  String toString([bool withBody]) {
    withBody ??= false;
    var infos = 'method: $method, requestedURL: $requestedURL, status: $status';
    if (withBody) infos += ', body: $body';
    return 'RESTResponse{$infos}';
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
typedef HttpBodyBuilder = dynamic Function(Map<String, String> parameters);
typedef HttpBodyBuilderTyped = dynamic Function(
    Map<String, String> parameters, String type);

/// Represents a body content, used by [HttpRequest].
class HttpBody {
  static final HttpBody NULL = HttpBody(null, null);

  /// Normalizes a Content-Type, allowing aliases like: json, png, jpeg and javascript.
  static String normalizeType(String bodyType) {
    return MimeType.parseAsString(bodyType);
  }

  ////////

  String _content;

  String _contentType;

  HttpBody(dynamic content, String type, [Map<String, String> parameters]) {
    _contentType = normalizeType(type);

    if (content is HttpBodyBuilder) {
      var f = content as HttpBodyBuilder;
      content = f(parameters ?? {});
    } else if (content is HttpBodyBuilderTyped) {
      var f = content as HttpBodyBuilderTyped;
      content = f(parameters ?? {}, _contentType);
    } else if (content is Function) {
      var f = content as Function;
      content = f();
    }

    if (content is String) {
      _content = content;
    } else if (isJSONType ||
        (_contentType == null && (content is Map || content is List))) {
      _content = encodeJSON(content);
      _contentType ??= MimeType.APPLICATION_JSON;
    } else if (content == null) {
      _content = null;
    } else {
      _content = '$content';
    }
  }

  /// Content of the body.
  String get content => _content;

  /// Type of the body (Content-Type header).
  String get contentType => _contentType;

  /// Returns [true] if has no content.
  bool get hasNoContent => _content == null;

  /// Returns [true] if has no [contentType].
  bool get hasNoContentType => _contentType == null;

  /// Returns [true] if [contentType] is a JSON (application/json).
  bool get isJSONType => _contentType != null && _contentType.endsWith('/json');

  /// Returns [true] if [hasNoContent] and [hasNoContentType].
  bool get isNull => hasNoContent && hasNoContentType;
}

typedef RequestHeadersBuilder = Map<String, String> Function(
    HttpClient client, String url);

typedef ResponseProcessor = void Function(
    HttpClient client, dynamic request, HttpResponse response);

typedef AuthorizationProvider = Future<Credential> Function(
    HttpClient client, HttpError lastError);

/// Represents a kind of HTTP Authorization.
abstract class Authorization {
  /// Copies this instance.
  Authorization copy();

  /// Returns [true] if the [Credential] is already resolved.
  bool get isCredentialResolved;

  /// Returns [true] if resolved [Credential] uses `Authorization` HTTP header.
  bool get usesAuthorizationHeader =>
      isCredentialResolved && resolvedCredential.usesAuthorizationHeader;

  /// Returns the resolved [Credential].
  ///
  /// Throws [StateError] if not resolved.
  Credential get resolvedCredential;

  /// Returns [true] if the [Credential] is static
  /// (future calls to [resolveCredential] will return the same instance).
  bool get isStaticCredential;

  /// Returns the resolved [Credential] or [null] if not resolved.
  Credential get tryResolvedCredential;

  /// Returns [true] if is in the process of [Credential] resolution.
  bool get isResolvingCredential => false;

  /// Resolves the actual [Credential] for the [HttpRequest].
  /// This method should cache the last resolved [Credential]
  /// and avoid unnecessary resolving procedures.
  Future<Credential> resolveCredential(HttpClient client, HttpError lastError);

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

  _AuthorizationStatic(this.credential) : super._() {
    if (credential == null) throw ArgumentError.notNull('credential');
  }

  @override
  Authorization copy() => _AuthorizationStatic(credential);

  @override
  bool get isCredentialResolved => credential != null;

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
          HttpClient client, HttpError lastError) async =>
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

  _AuthorizationResolvable(this.authorizationProvider) : super._() {
    if (authorizationProvider == null) {
      throw ArgumentError.notNull('authorizationProvider');
    }
  }

  /// Copies this instance.
  @override
  Authorization copy() {
    var authorization = _AuthorizationResolvable(authorizationProvider);
    authorization._resolvedCredential = _resolvedCredential;
    return authorization;
  }

  Credential _resolvedCredential;

  /// Returns [true] if the [Credential] is already resolved.
  @override
  bool get isCredentialResolved => _resolvedCredential != null;

  @override
  bool get isStaticCredential => false;

  @override
  Credential get resolvedCredential {
    if (!isCredentialResolved) throw StateError('Credential not resolved');
    return _resolvedCredential;
  }

  @override
  Credential get tryResolvedCredential => _resolvedCredential;

  Future<Credential> _resolveFuture;

  @override
  bool get isResolvingCredential => _resolveFuture != null;

  /// Resolve the actual [Credential] for the [HttpRequest].
  @override
  Future<Credential> resolveCredential(
      HttpClient client, HttpError lastError) async {
    if (_resolvedCredential != null) return _resolvedCredential;

    if (_resolveFuture != null) {
      var credential = await _resolveFuture;
      return _resolvedCredential ?? credential;
    }

    _resolveFuture = authorizationProvider(client, lastError);

    var credential = await _resolveFuture;
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
  String buildAuthorizationHeaderLine() {
    return null;
  }

  /// Builds the [HttpRequest] URL. Used by credentials that injects tokens/credentials in the URL.
  String buildURL(String url) {
    return null;
  }

  /// Builds the [HttpRequest] body. Used by credentials that injects tokens/credentials in the body.
  HttpBody buildBody(HttpBody body) {
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

  factory BasicCredential.fromJSON(dynamic json) {
    if (json == null) return null;

    if (json is List) {
      if (json.length < 2) return null;
      return BasicCredential(json[0], json[1]);
    } else if (json is Map) {
      if (json.length < 2) return null;

      var user = findKeyValue(
          json, ['username', 'user', 'login', 'email', 'account'], true);
      var pass =
          findKeyValue(json, ['password', 'pass', 'secret', 'token'], true);

      return BasicCredential(user, pass);
    } else if (json is String) {
      var parts = json.split(RegExp(r'[:;\s]+'));
      if (parts.length < 2) return null;
      return BasicCredential(parts[0], parts[1]);
    }
    return null;
  }

  /// Instantiate using a base64 encoded credential, in format  `$username:$password`.
  factory BasicCredential.base64(String base64) {
    var decodedBytes = Base64Codec.urlSafe().decode(base64);
    var decoded = String.fromCharCodes(decodedBytes);
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
    if (json.isEmpty || tokenKey == null || tokenKey.isEmpty) return null;

    var tokenKeys = tokenKey.split('/');

    dynamic token = findKeyValue(json, [tokenKeys.removeAt(0)], true);
    if (token == null) return null;

    for (var k in tokenKeys) {
      if (token is Map) {
        token = findKeyValue(token, [k], true);
      } else if (token is List && isInt(k)) {
        var idx = parseInt(k);
        token = token[idx];
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

  static const List<String> _DEFAULT_EXTRA_TOKEN_KEYS = [
    'accessToken',
    'accessToken/token'
  ];

  /// Instance from a JSON.
  ///
  /// [mainTokenKey] default: `access_token`.
  /// [extraTokenKeys]: `accessToken`, `accessToken/token`.
  factory BearerCredential.fromJSONToken(dynamic json,
      [String mainTokenKey = 'access_token',
      List<String> extraTokenKeys = _DEFAULT_EXTRA_TOKEN_KEYS]) {
    if (json is Map) {
      var token =
          findKeyPathValue(json, mainTokenKey, isValidValue: isValidTokenValue);

      if (token == null && extraTokenKeys != null) {
        for (var key in extraTokenKeys) {
          token = findKeyPathValue(json, key, isValidValue: isValidTokenValue);
          if (token != null) break;
        }
      }

      if (token != null) {
        var tokenStr = token.toString().trim();
        return tokenStr != null && tokenStr.isNotEmpty
            ? BearerCredential(tokenStr)
            : null;
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

/// A [Credential] that injects fields in the Query paramaters.
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
  String _field;

  /// Authorization JSON tree.
  final dynamic authorization;

  JSONBodyCredential(String field, this.authorization) {
    if (field != null) {
      field = field.trim();
      _field = field.isNotEmpty ? field : null;
    }
  }

  /// JSON field name.
  String get field => _field;

  /// Returns `jsonbody`.
  @override
  String get type => 'jsonbody';

  /// Returns [false].
  @override
  bool get usesAuthorizationHeader => false;

  @override
  String buildAuthorizationHeaderLine() {
    return null;
  }

  /// Won't change the parameter [url].
  @override
  String buildURL(String url) {
    return url;
  }

  /// Builds the [HttpRequest] body with the [Credential].
  @override
  HttpBody buildBody(HttpBody body) {
    if (body == null || body.isNull) {
      return buildJSONAuthorizationBody(null);
    } else if (body.isJSONType) {
      return buildJSONAuthorizationBody(body.content);
    } else {
      return body;
    }
  }

  HttpBody buildJSONAuthorizationBody(String body) {
    return HttpBody(buildJSONAuthorizationBodyJSON(body), 'application/json');
  }

  String buildJSONAuthorizationBodyJSON(String body) {
    if (body == null) {
      if (field == null || field.isEmpty) {
        return encodeJSON(authorization);
      } else {
        return encodeJSON({'$field': authorization});
      }
    }

    var bodyJson = json.decode(body);

    if (field == null || field.isEmpty) {
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
String buildURLWithQueryParameters(String url, Map<String, String> parameters,
    {bool removeFragment = false}) {
  if (parameters == null || parameters.isEmpty) return url;

  var uri = Uri.parse(url);

  Map<String, String> queryParameters;

  if (uri.query == null || uri.query.isEmpty) {
    queryParameters = Map.from(parameters);
  } else {
    queryParameters = uri.queryParameters ?? {};
    queryParameters = Map.from(queryParameters);
    queryParameters.addAll(parameters);
  }

  var fragment = uri.fragment;
  if ((removeFragment ?? false) || (fragment != null && fragment.isEmpty)) {
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
enum HttpMethod { GET, OPTIONS, POST, PUT, DELETE, PATCH, HEAD }

bool methodAcceptsQueryString(HttpMethod method) {
  return method == HttpMethod.GET || method == HttpMethod.OPTIONS;
}

/// Returns [HttpMethod] instance for [method] parameter.
HttpMethod getHttpMethod(String method, [HttpMethod def]) {
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
  if (method == null) return false;

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
String getHttpMethodName(HttpMethod method, [HttpMethod def]) {
  method ??= def;

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
    default:
      return null;
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
  final Map<String, String> queryParameters;

  /// Authorization instance for the request.
  final Authorization authorization;

  final bool withCredentials;

  /// Tells the server the desired response format.
  final String responseType;

  /// MimeType of request sent data (body).
  final String mimeType;

  /// Headers of the request.
  final Map<String, String> requestHeaders;

  /// Data/body to send with the request.
  final dynamic sendData;

  int _retries = 0;

  HttpRequest(this.method, this.url, this.requestURL,
      {this.queryParameters,
      this.authorization,
      this.withCredentials,
      this.responseType,
      this.mimeType,
      this.requestHeaders,
      this.sendData});

  /// Copies this instance with a different [client] and [authorization] if provided.
  HttpRequest copy([HttpClient client, Authorization authorization]) {
    if (authorization == null || authorization == this.authorization) {
      return this;
    }

    var requestHeaders = client.clientRequester.buildRequestHeaders(
        client, url, authorization, sendData, headerContentType, headerAccept);

    // ignore: omit_local_variable_types
    Map<String, String> queryParameters =
        this.queryParameters != null ? Map.from(this.queryParameters) : null;
    var requestURL = client.clientRequester
        .buildRequestURL(client, url, authorization, queryParameters);

    var copy = HttpRequest(method, url, requestURL,
        queryParameters: queryParameters,
        authorization: authorization,
        withCredentials: withCredentials,
        responseType: responseType,
        mimeType: mimeType,
        requestHeaders: requestHeaders,
        sendData: sendData);
    copy._retries = _retries;

    return copy;
  }

  /// Returns the header: Accept
  String get headerAccept =>
      requestHeaders != null ? requestHeaders['Accept'] : null;

  /// Returns the header: Content-Type
  String get headerContentType =>
      requestHeaders != null ? requestHeaders['Content-Type'] : null;

  /// Number of retries for this request.
  int get retries => _retries;

  void incrementRetries() {
    _retries++;
  }

  @override
  String toString() {
    return 'HttpRequest{method: $method, url: $url, requestURL: $requestURL, retries: $_retries, queryParameters: $queryParameters, authorization: $authorization, withCredentials: $withCredentials, responseType: $responseType, mimeType: $mimeType, requestHeaders: $requestHeaders, sendData: $sendData}';
  }
}

/// Abstract [HttpClient] requester. This should implement the actual
/// request process.
abstract class HttpClientRequester {
  Future<HttpResponse> request(HttpClient client, HttpMethod method, String url,
      {Authorization authorization,
      Map<String, String> queryParameters,
      dynamic body,
      String contentType,
      String accept}) {
    switch (method) {
      case HttpMethod.GET:
        return requestGET(client, url,
            authorization: authorization, queryParameters: queryParameters);
      case HttpMethod.OPTIONS:
        return requestOPTIONS(client, url,
            authorization: authorization, queryParameters: queryParameters);
      case HttpMethod.POST:
        return requestPOST(client, url,
            authorization: authorization,
            queryParameters: queryParameters,
            body: body,
            contentType: contentType,
            accept: accept);
      case HttpMethod.PUT:
        return requestPUT(client, url,
            authorization: authorization,
            body: body,
            contentType: contentType,
            accept: accept);
      case HttpMethod.PATCH:
        return requestPATCH(client, url,
            authorization: authorization,
            body: body,
            contentType: contentType,
            accept: accept);
      case HttpMethod.DELETE:
        return requestDELETE(client, url,
            authorization: authorization,
            body: body,
            contentType: contentType,
            accept: accept);

      default:
        throw StateError(
            "Can't handle method: ${EnumToString.convertToString(method)}");
    }
  }

  bool _withCredentials(HttpClient client, Authorization authorization) {
    if (client.crossSiteWithCredentials != null) {
      return client.crossSiteWithCredentials;
    }

    if (authorization != null && authorization.usesAuthorizationHeader) {
      return true;
    } else {
      return false;
    }
  }

  Future<HttpResponse> requestGET(HttpClient client, String url,
      {Authorization authorization, Map<String, String> queryParameters}) {
    return doHttpRequest(
        client,
        HttpRequest(HttpMethod.GET, url,
            buildRequestURL(client, url, authorization, queryParameters),
            authorization: authorization,
            queryParameters: queryParameters,
            withCredentials: _withCredentials(client, authorization),
            requestHeaders: buildRequestHeaders(client, url, authorization)),
        client.logRequests);
  }

  Future<HttpResponse> requestOPTIONS(HttpClient client, String url,
      {Authorization authorization, Map<String, String> queryParameters}) {
    return doHttpRequest(
        client,
        HttpRequest(HttpMethod.OPTIONS, url,
            buildRequestURL(client, url, authorization, queryParameters),
            authorization: authorization,
            queryParameters: queryParameters,
            withCredentials: _withCredentials(client, authorization),
            requestHeaders: buildRequestHeaders(client, url, authorization)),
        client.logRequests);
  }

  Future<HttpResponse> requestPOST(HttpClient client, String url,
      {Authorization authorization,
      Map<String, String> queryParameters,
      dynamic body,
      String contentType,
      String accept}) {
    var httpBody = HttpBody(body, contentType, queryParameters);
    var requestBody = buildRequestBody(client, httpBody, authorization);

    if (queryParameters != null &&
        queryParameters.isNotEmpty &&
        requestBody.isNull) {
      var requestHeaders = buildRequestHeaders(client, url, authorization,
          requestBody.content, requestBody.contentType, accept);
      requestHeaders ??= {};

      var formData = buildPOSTFormData(queryParameters, requestHeaders);
      if (requestHeaders.isEmpty) requestHeaders = null;

      return doHttpRequest(
          client,
          HttpRequest(
              HttpMethod.POST, url, buildRequestURL(client, url, authorization),
              authorization: authorization,
              queryParameters: queryParameters,
              withCredentials: _withCredentials(client, authorization),
              requestHeaders: requestHeaders,
              sendData: formData),
          client.logRequests);
    } else {
      return doHttpRequest(
          client,
          HttpRequest(HttpMethod.POST, url,
              buildRequestURL(client, url, authorization, queryParameters),
              authorization: authorization,
              queryParameters: queryParameters,
              withCredentials: _withCredentials(client, authorization),
              requestHeaders: buildRequestHeaders(client, url, authorization,
                  requestBody.content, requestBody.contentType, accept),
              sendData: requestBody.content),
          client.logRequests);
    }
  }

  Future<HttpResponse> requestPUT(HttpClient client, String url,
      {Authorization authorization,
      Map<String, String> queryParameters,
      dynamic body,
      String contentType,
      String accept}) {
    var httpBody = HttpBody(body, contentType, queryParameters);
    var requestBody = buildRequestBody(client, httpBody, authorization);

    return doHttpRequest(
        client,
        HttpRequest(
            HttpMethod.PUT, url, buildRequestURL(client, url, authorization),
            authorization: authorization,
            queryParameters: queryParameters,
            withCredentials: _withCredentials(client, authorization),
            requestHeaders: buildRequestHeaders(client, url, authorization,
                requestBody.content, requestBody.contentType, accept),
            sendData: requestBody.content),
        client.logRequests);
  }

  Future<HttpResponse> requestPATCH(HttpClient client, String url,
      {Authorization authorization,
      Map<String, String> queryParameters,
      dynamic body,
      String contentType,
      String accept}) {
    var httpBody = HttpBody(body, contentType, queryParameters);
    var requestBody = buildRequestBody(client, httpBody, authorization);

    return doHttpRequest(
        client,
        HttpRequest(
            HttpMethod.PATCH, url, buildRequestURL(client, url, authorization),
            authorization: authorization,
            queryParameters: queryParameters,
            withCredentials: _withCredentials(client, authorization),
            requestHeaders: buildRequestHeaders(client, url, authorization,
                requestBody.content, requestBody.contentType, accept),
            sendData: requestBody.content),
        client.logRequests);
  }

  Future<HttpResponse> requestDELETE(HttpClient client, String url,
      {Authorization authorization,
      Map<String, String> queryParameters,
      dynamic body,
      String contentType,
      String accept}) {
    var httpBody = HttpBody(body, contentType, queryParameters);
    var requestBody = buildRequestBody(client, httpBody, authorization);

    return doHttpRequest(
        client,
        HttpRequest(
            HttpMethod.DELETE, url, buildRequestURL(client, url, authorization),
            authorization: authorization,
            queryParameters: queryParameters,
            withCredentials: _withCredentials(client, authorization),
            requestHeaders: buildRequestHeaders(client, url, authorization,
                requestBody.content, requestBody.contentType, accept),
            sendData: requestBody.content),
        client.logRequests);
  }

  /// Implements teh actual HTTP request for imported platform.
  Future<HttpResponse> doHttpRequest(
      HttpClient client, HttpRequest request, bool log);

  String buildPOSTFormData(Map<String, String> data,
      [Map<String, String> requestHeaders]) {
    var formData = buildQueryString(data);

    if (requestHeaders != null) {
      requestHeaders.putIfAbsent('Content-Type',
          () => 'application/x-www-form-urlencoded; charset=UTF-8');
    }

    return formData;
  }

  /// Helper to build a Query String.
  String buildQueryString(Map<String, String> data) {
    var parts = [];
    data.forEach((key, value) {
      var keyValue =
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}';
      parts.add(keyValue);
    });

    var queryString = parts.join('&');
    return queryString;
  }

  /// Helper to build the request headers.
  Map<String, String> buildRequestHeaders(HttpClient client, String url,
      [Authorization authorization,
      dynamic body,
      String contentType,
      String accept]) {
    var header = client.buildRequestHeaders(url);

    if (contentType != null) {
      header ??= {};
      header['Content-Type'] = contentType;
    }

    if (accept != null) {
      header ??= {};
      header['Accept'] = accept;
    }

    if (authorization != null && authorization.usesAuthorizationHeader) {
      header ??= {};

      var credential = authorization.resolvedCredential;
      var authorizationHeaderLine = credential.buildAuthorizationHeaderLine();
      if (authorizationHeaderLine != null) {
        header['Authorization'] = authorizationHeaderLine;
      }
    }

    return header;
  }

  /// Helper to build the request URL.
  String buildRequestURL(HttpClient client, String url,
      [Authorization authorization, Map<String, String> queryParameters]) {
    if (queryParameters != null && queryParameters.isNotEmpty) {
      url = buildURLWithQueryParameters(url, queryParameters,
          removeFragment: true);
    }

    if (authorization != null && authorization.isCredentialResolved) {
      var authorizationURL = authorization.resolvedCredential.buildURL(url);
      if (authorizationURL != null) return authorizationURL;
    }

    return url;
  }

  /// Helper to build the request body.
  HttpBody buildRequestBody(
      HttpClient client, HttpBody httpBody, Authorization authorization) {
    if (authorization != null && authorization.isCredentialResolved) {
      var jsonBody = authorization.resolvedCredential.buildBody(httpBody);
      if (jsonBody != null) return jsonBody;
    }

    return httpBody ?? HttpBody.NULL;
  }

  /// Closes the [HttpClientRequester] and internal instances.
  void close() {}
}

typedef HttpClientURLFilter = String Function(
    String url, Map<String, String> queryParameters);

typedef AuthorizationInterceptor = void Function(Authorization authorization);

/// Represents a simple HTTP call that can be called many times.
class HttpCall<R> {
  final HttpClient client;
  final HttpMethod method;
  final String path;
  final bool fullPath;
  final dynamic body;
  final int maxRetries;

  HttpCall(
      {String baseURL,
      HttpClient client,
      HttpMethod method,
      String path,
      bool fullPath,
      this.body,
      int maxRetries})
      : client = client ?? HttpClient(baseURL ?? getUriBase().toString()),
        method = method ?? HttpMethod.GET,
        path = path ?? '',
        fullPath = fullPath ?? false,
        maxRetries = maxRetries ?? 0;

  /// Performs a call, making the HTTP request.
  Future<HttpResponse> call(Map<String, dynamic> parameters,
      {dynamic body, int maxRetries}) async {
    maxRetries ??= this.maxRetries;

    var limit = Math.max(1, 1 + maxRetries);

    var response;

    for (var i = 0; i < limit; i++) {
      response = await _doRequestImp(parameters, body);
      if (response.isOK) {
        return response;
      }
    }

    return response;
  }

  /// Performs a call, making the HTTP request, than resolves the response.
  Future<R> callAndResolve(Map<String, dynamic> parameters,
      {dynamic body, int maxRetries}) async {
    var response = await call(parameters, body: body, maxRetries: maxRetries);
    return resolveResponse(response);
  }

  Future<HttpResponse> _doRequestImp(
      Map<String, dynamic> parameters, dynamic body) async {
    if (canHttpMethodHaveBody(method)) {
      body ??= this.body;
    } else {
      body = null;
    }

    var response = await requestHttpClient(
        client, method, path, fullPath, parameters, body);
    return response;
  }

  static Map<String, String> toQueryParameters(Map parameters) {
    Map<String, String> queryParameters;
    if (parameters != null) {
      queryParameters = parameters
          .map((key, value) => MapEntry('$key', toQueryParameterValue(value)));
    }
    return queryParameters;
  }

  static String toQueryParameterValue(dynamic value) {
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
      String path, bool fullPath, Map parameters, dynamic body) {
    var queryParameters = toQueryParameters(parameters);
    return client.request(method, path,
        fullPath: fullPath, parameters: queryParameters, body: body);
  }

  /// Method responsible to resolve the [response] to a [R] value.
  ///
  /// Can be overwritten by other implementations.
  R resolveResponse(HttpResponse response) {
    if (!response.isOK) {
      throw StateError(
          "Can't perform request. Response{ status: ${response.status} ; body: ${response.body}} > $this");
    } else if (response.isBodyTypeJSON) {
      return response.json as R;
    } else {
      return response.body as R;
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
  String baseURL;

  /// Requester implementation.
  HttpClientRequester _clientRequester;

  /// Returns the [HttpClientRequester] instance.
  HttpClientRequester get clientRequester => _clientRequester;

  static int _idCounter = 0;

  int _id;

  HttpClient(String baseURL, [HttpClientRequester clientRequester]) {
    _id = ++_idCounter;

    if (baseURL.endsWith('/')) {
      baseURL = baseURL.substring(0, baseURL.length - 1);
    }

    if (baseURL == null || baseURL.isEmpty) {
      throw ArgumentError('Invalid baseURL');
    }

    this.baseURL = baseURL;

    _clientRequester = clientRequester ?? createHttpClientRequester();
  }

  /// The URL filter, if present.
  HttpClientURLFilter urlFilter;

  @override
  String toString() {
    return 'HttpClient{id: $_id, baseURL: $baseURL, authorization: $authorization, crossSiteWithCredentials: $crossSiteWithCredentials, logJSON: $logJSON, _clientRequester: $_clientRequester}';
  }

  /// ID of this client.
  int get id => _id;

  /// Returns [true] if this [baseURL] is `localhost`.
  bool isBaseUrlLocalhost() {
    var uri = Uri.parse(baseURL);
    return isLocalhost(uri.host);
  }

  /// Requests using [method] and [path] and returns a decoded JSON.
  Future<dynamic> requestJSON(HttpMethod method, String path,
      {Credential authorization,
      Map<String, String> queryParameters,
      dynamic body,
      String contentType,
      String accept}) async {
    return request(method, path,
            authorization: authorization,
            parameters: queryParameters,
            body: body,
            contentType: contentType,
            accept: accept)
        .then((r) => _jsonDecode(r.body));
  }

  /// Does a GET request and returns a decoded JSON.
  Future<dynamic> getJSON(String path,
      {Credential authorization, Map<String, String> parameters}) async {
    return get(path, authorization: authorization, parameters: parameters)
        .then((r) => _jsonDecode(r.body));
  }

  /// Does an OPTION request and returns a decoded JSON.
  Future<dynamic> optionsJSON(String path,
      {Credential authorization, Map<String, String> parameters}) async {
    return options(path, authorization: authorization, parameters: parameters)
        .then((r) => _jsonDecode(r.body));
  }

  /// Does a POST request and returns a decoded JSON.
  Future<dynamic> postJSON(String path,
      {Credential authorization,
      Map<String, String> parameters,
      dynamic body,
      String contentType}) async {
    return post(path,
            authorization: authorization,
            parameters: parameters,
            body: body,
            contentType: contentType)
        .then((r) => _jsonDecode(r.body));
  }

  /// Does a PUT request and returns a decoded JSON.
  Future<dynamic> putJSON(String path,
      {Credential authorization, dynamic body, String contentType}) async {
    return put(path,
            authorization: authorization, body: body, contentType: contentType)
        .then((r) => _jsonDecode(r.body));
  }

  /// If set to true, sends credential to cross sites.
  bool crossSiteWithCredentials;

  Authorization _authorization;

  /// The [Authorization] (that resolves [Credential]) for requests.
  Authorization get authorization => _authorization;

  set authorization(Authorization authorization) {
    _authorization = authorization;
    _notifyResolvedAuthorization();
  }

  void _notifyResolvedAuthorization() {
    if (_authorization != null &&
        authorizationResolutionInterceptor != null &&
        _authorization.isCredentialResolved) {
      try {
        authorizationResolutionInterceptor(_authorization);
      } catch (e, s) {
        print(e);
        print(s);
      }
    }
  }

  AuthorizationInterceptor authorizationResolutionInterceptor;

  String _responseHeaderWithToken;

  /// The response header with a token to use as [authorization] [Credential].
  String get responseHeaderWithToken => _responseHeaderWithToken;

  /// If set, will automatically use a token in the
  /// header [responseHeaderWithToken], when found in any request.
  HttpClient autoChangeAuthorizationToBearerToken(
      String responseHeaderWithToken) {
    _responseHeaderWithToken = responseHeaderWithToken;
    return this;
  }

  bool logRequests = false;

  bool logJSON = false;

  dynamic _jsonDecode(String s) {
    if (logJSON) _logJSON(s);

    return jsonDecode(s);
  }

  void _logJSON(String json) {
    var now = DateTime.now();
    print('$now> HttpClient> $json');
  }

  Future<Authorization> _buildRequestAuthorization(
      Credential credential) async {
    if (credential != null) {
      return Authorization.fromCredential(credential);
    }

    return _resolveAuthorization();
  }

  /// Returns [true] if [authorization] is resolved.
  bool get isAuthorizationResolved =>
      authorization != null && authorization.isCredentialResolved;

  /// Returns the [authorization] if is resolved.
  Authorization get resolvedAuthorization =>
      isAuthorizationResolved ? authorization : null;

  Future<Authorization> _resolveAuthorization() async {
    if (_authorization == null) return Future.value(null);

    if (_authorization.isResolvingCredential) {
      print('WARNING: '
          'Authorization[${_authorization.runtimeType}] is already resolving a credential! '
          '(NOTE: Do not use this client instance for network resolution while resolving a Credential)');
    }

    await _authorization.resolveCredential(this, null);
    _notifyResolvedAuthorization();
    return _authorization;
  }

  /// Does a request using [method].
  Future<HttpResponse> request(HttpMethod method, String path,
      {bool fullPath,
      Credential authorization,
      Map<String, String> parameters,
      dynamic body,
      String contentType,
      String accept}) async {
    var url = buildMethodRequestURL(method, path, fullPath, parameters);

    var ret_url_parameters = _build_URL_and_Parameters(
        url, parameters, methodAcceptsQueryString(method));

    url = ret_url_parameters.key;
    parameters = ret_url_parameters.value;

    return requestURL(method, url,
        authorization: authorization,
        queryParameters: parameters,
        body: body,
        contentType: contentType,
        accept: accept);
  }

  /// Builds the URL for [method] using [path] or [fullPath].
  String buildMethodRequestURL(HttpMethod method, String path, bool fullPath,
          Map<String, String> parameters) =>
      _buildURL(path, fullPath, parameters, methodAcceptsQueryString(method));

  Future<HttpResponse> requestURL(HttpMethod method, String url,
      {Credential authorization,
      Map<String, String> queryParameters,
      dynamic body,
      String contentType,
      String accept}) async {
    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.request(this, method, url,
        authorization: requestAuthorization,
        queryParameters: queryParameters,
        body: body,
        contentType: contentType,
        accept: accept);
  }

  //////////////

  /// Does a GET request.
  Future<HttpResponse> get(String path,
      {bool fullPath,
      Credential authorization,
      Map<String, String> parameters}) async {
    var url = _buildURL(path, fullPath, parameters, true);
    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestGET(this, url,
        authorization: requestAuthorization);
  }

  /// Does an OPTIONS request.
  Future<HttpResponse> options(String path,
      {bool fullPath,
      Credential authorization,
      Map<String, String> parameters}) async {
    var url = _buildURL(path, fullPath, parameters, true);
    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestOPTIONS(this, url,
        authorization: requestAuthorization);
  }

  /// Does a POST request.
  Future<HttpResponse> post(String path,
      {bool fullPath,
      Credential authorization,
      Map<String, String> parameters,
      dynamic body,
      String contentType,
      String accept}) async {
    var url = _buildURL(path, fullPath, parameters);

    var ret_url_parameters = _build_URL_and_Parameters(url, parameters, false);
    url = ret_url_parameters.key;
    parameters = ret_url_parameters.value;

    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestPOST(this, url,
        authorization: requestAuthorization,
        queryParameters: parameters,
        body: body,
        contentType: contentType,
        accept: accept);
  }

  /// Does a PUT request.
  Future<HttpResponse> put(String path,
      {bool fullPath,
      Credential authorization,
      Map<String, String> parameters,
      dynamic body,
      String contentType,
      String accept}) async {
    var url = _buildURL(path, fullPath, parameters);

    var ret_url_parameters = _build_URL_and_Parameters(url, parameters, false);
    url = ret_url_parameters.key;
    parameters = ret_url_parameters.value;

    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestPUT(this, url,
        authorization: requestAuthorization,
        queryParameters: parameters,
        body: body,
        contentType: contentType,
        accept: accept);
  }

  /// Does a PATCH request.
  Future<HttpResponse> patch(String path,
      {bool fullPath,
      Credential authorization,
      Map<String, String> parameters,
      dynamic body,
      String contentType,
      String accept}) async {
    var url = _buildURL(path, fullPath, parameters);

    var ret_url_parameters = _build_URL_and_Parameters(url, parameters, false);
    url = ret_url_parameters.key;
    parameters = ret_url_parameters.value;

    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestPATCH(this, url,
        authorization: requestAuthorization,
        queryParameters: parameters,
        body: body,
        contentType: contentType,
        accept: accept);
  }

  /// Does a DELETE request.
  Future<HttpResponse> delete(String path,
      {bool fullPath,
      Credential authorization,
      Map<String, String> parameters,
      dynamic body,
      String contentType,
      String accept}) async {
    var url = _buildURL(path, fullPath, parameters);

    var ret_url_parameters = _build_URL_and_Parameters(url, parameters, false);
    url = ret_url_parameters.key;
    parameters = ret_url_parameters.value;

    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestDELETE(this, url,
        authorization: requestAuthorization,
        queryParameters: parameters,
        body: body,
        contentType: contentType,
        accept: accept);
  }

  //////////////

  Uri _removeURIQueryParameters(Uri uri) {
    if (uri.scheme.toLowerCase() == 'https') {
      return Uri.https(uri.authority, Uri.decodeComponent(uri.path));
    } else {
      return Uri.http(uri.authority, Uri.decodeComponent(uri.path));
    }
  }

  MapEntry<String, Map<String, String>> _build_URL_and_Parameters(
      String url, Map<String, String> parameters, bool allowURLQueryString) {
    var uri = Uri.parse(url);

    if (uri.queryParameters != null && uri.queryParameters.isNotEmpty) {
      if (parameters != null && parameters.isNotEmpty) {
        uri.queryParameters
            .forEach((k, v) => parameters.putIfAbsent(k, () => v));
      } else {
        parameters = uri.queryParameters;
      }

      url = _removeURIQueryParameters(uri).toString();
    }

    return MapEntry(url, parameters);
  }

  /// Builds a request URL, using [baseURL] with [path] or [fullPath].
  String buildRequestURL(String path, bool fullPath,
      [Map<String, String> queryParameters, bool allowURLQueryString = true]) {
    return _buildURL(path, fullPath, queryParameters, allowURLQueryString);
  }

  String _buildURL(String path, bool fullPath, Map<String, String> parameters,
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
      path = buildStringPattern(path, parameters ?? {});
    }

    if (!path.startsWith('/')) path = '/$path';

    var url;

    if (fullPath != null && fullPath) {
      var uri = Uri.parse(baseURL);

      var uri2;
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
      var url2 = urlFilter(url, queryParameters);
      if (url2 != null && url2.isNotEmpty && url2 != url) {
        url = url2;
      }
    }

    return _buildURLWithParameters(url, queryParameters);
  }

  String _buildURLWithParameters(
      String url, Map<String, String> queryParameters) {
    var uri = Uri.parse(url);

    var uriParameters = uri.queryParameters;

    if (uriParameters != null && uriParameters.isNotEmpty) {
      if (queryParameters == null || queryParameters.isEmpty) {
        queryParameters = uriParameters;
      } else {
        uriParameters
            .forEach((k, v) => queryParameters.putIfAbsent(k, () => v));
      }
    }

    if (queryParameters != null && queryParameters.isEmpty) {
      queryParameters = null;
    }

    var uri2;

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
  ResponseProcessor responseProcessor;

  /// Builds initial headers for each request.
  RequestHeadersBuilder requestHeadersBuilder;

  Map<String, String> buildRequestHeaders(String url) {
    if (requestHeadersBuilder == null) return null;
    return requestHeadersBuilder(this, url);
  }
}

typedef SimulateResponse = String Function(
    String url, Map<String, String> queryParameters);

/// A Simulated [HttpClientRequester]. Usefull for tests and mocks.
class HttpClientRequesterSimulation extends HttpClientRequester {
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
        return _getPatterns ?? _anyPatterns;
      case HttpMethod.OPTIONS:
        return _optionsPatterns ?? _anyPatterns;
      case HttpMethod.PUT:
        return _putPatterns ?? _anyPatterns;
      case HttpMethod.POST:
        return _postPatterns ?? _anyPatterns;
      default:
        return _anyPatterns;
    }
  }

  SimulateResponse _findResponse(
      String url, Map<RegExp, SimulateResponse> patterns) {
    if (patterns == null || patterns.isEmpty) return null;

    for (var p in patterns.keys) {
      if (p.hasMatch(url)) {
        return patterns[p];
      }
    }
    return null;
  }

  /// Implementation for simulated requests.
  @override
  Future<HttpResponse> doHttpRequest(
      HttpClient client, HttpRequest request, bool log) {
    var methodPatterns = getSimulationPatternsByMethod(request.method);
    return _requestSimulated(client, request.method, request.requestURL,
        methodPatterns, request.queryParameters);
  }

  Future<HttpResponse> _requestSimulated(
      HttpClient client,
      HttpMethod method,
      String url,
      Map<RegExp, SimulateResponse> methodPatterns,
      Map<String, String> queryParameters) {
    var resp =
        _findResponse(url, methodPatterns) ?? _findResponse(url, _anyPatterns);

    if (resp == null) {
      return Future.error('No simulated response[$method]');
    }

    var respVal = resp(url, queryParameters);

    var restResponse = HttpResponse(method, url, url, 200, respVal);

    return Future.value(restResponse);
  }
}

/// Returns de decoder for a Content-Type at parameter [mimeType] and [charset].
Converter<List<int>, String> contentTypeToDecoder(String mimeType,
    [String charset]) {
  if (charset != null) {
    charset = charset.trim().toLowerCase();

    if (charset == 'utf8' || charset == 'utf-8') {
      return utf8.decoder;
    } else if (charset == 'latin1' ||
        charset == 'latin-1' ||
        charset == 'iso-8859-1') {
      return latin1.decoder;
    }
  }

  if (mimeType != null) {
    mimeType = mimeType.trim().toLowerCase();

    if (mimeType == 'application/json') {
      return utf8.decoder;
    } else if (mimeType == 'application/x-www-form-urlencoded') {
      return latin1.decoder;
    }
  }

  return latin1.decoder;
}

/// Creates a HttpClientRequester based in imported platform.
HttpClientRequester createHttpClientRequester() {
  return createHttpClientRequesterImpl();
}

/// Returns the base runtime Uri for the platform.
Uri getHttpClientRuntimeUri() {
  return getHttpClientRuntimeUriImpl();
}
