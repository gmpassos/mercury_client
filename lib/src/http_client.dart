import 'dart:async';
import 'dart:convert';

import 'package:enum_to_string/enum_to_string.dart';
import 'package:mercury_client/mercury_client.dart';
import 'package:swiss_knife/swiss_knife.dart';

import 'http_client_none.dart'
if (dart.library.html) "http_client_browser.dart"
if (dart.library.io) "http_client_io.dart" ;


///////////////////////////////////////////////////////

typedef ResponseHeaderGetter = String Function(String headerKey) ;


class HttpStatus {

  final String url ;
  final String requestedURL ;
  final int status ;

  HttpStatus(this.url, this.requestedURL, this.status);

  /////

  bool get isOK => isStatusSuccessful ;
  bool get isError => isStatusError ;

  bool get isStatusSuccessful => isStatusInRange(200, 299) ;

  bool get isStatusNotFound => isStatus(404) ;

  bool get isStatusUnauthenticated => isStatus(401) ;

  bool get isStatusNetworkError => status == null || status <= 0 ;

  bool get isStatusServerError => isStatusInRange(500, 599) ;

  bool get isStatusAccessError => isStatusInRange(405 , 418) || isStatusInList([ 400 , 403 , 431 , 451 ])  ;

  bool get isStatusError => isStatusNetworkError || isStatusServerError || isStatusAccessError ;

  /////

  bool isStatus( int status ) {
    return this.status != null && this.status == status ;
  }

  bool isStatusInRange( int statusInit , int statusEnd ) {
    return status != null && status >= statusInit && status <= statusEnd ;
  }

  bool isStatusInList( List<int> statusList ) {
    return status != null && ( statusList.firstWhere( (id) => id == status , orElse: () => null ) != null ) ;
  }

}


class HttpError extends HttpStatus {

  final String message ;
  final dynamic error ;

  HttpError(String url, String requestedURL, int status, this.message, this.error) : super(url, requestedURL, status) ;

  bool get hasMessage => message != null && message.isNotEmpty ;

  bool get isOAuthAuthorizationError {
    if ( !hasMessage ) return false ;

    var authorizationCode = status == 0 || status == 400 || status == 401 ;
    if ( !authorizationCode ) return false ;

    return matchesAnyJSONEntry( 'error' , ['invalid_grant','invalid_client','unauthorized_client'] , true ) ;
  }

  bool matchesAnyJSONEntry(String key, List<String> values, bool text) {
    if ( key == null || values == null || key.isEmpty || values.isEmpty || !hasMessage ) return false ;

    for (var value in values) {
      if ( matchesJSONEntry(key, value, text) ) return true ;
    }

    return false ;
  }

  bool matchesJSONEntry(String key, String value, bool text) {
    if ( hasMessage && message.contains(key) && message.contains(value) ) {
      var entryValue = text ? '"$value"' : '$value' ;
      return RegExp('"$key":\\s*$entryValue').hasMatch( message ) ;
    }
    return false ;
  }

  @override
  String toString() {
    return 'RESTError{requestedURL: $requestedURL, status: $status, message: $message, error: $error}';
  }

}

class HttpResponse extends HttpStatus implements Comparable<HttpResponse> {
  final String method ;
  final String body ;
  final ResponseHeaderGetter _responseHeaderGetter ;
  final dynamic request ;

  final int instanceTime = DateTime.now().millisecondsSinceEpoch ;
  int _accessTime ;

  HttpResponse(this.method, String url, String requestedURL, int status, this.body, [this._responseHeaderGetter, this.request]) : super(url, requestedURL, status) {
    _accessTime = instanceTime ;
  }

  int get accessTime => _accessTime;

  void updateAccessTime() {
    _accessTime = DateTime.now().millisecondsSinceEpoch ;
  }

  int memorySize() {
    var memory = 1 + 8 + 8 + (method != null ? method.length : 0) + (body != null ? body.length : 0) + (url == requestedURL ? url.length : url.length + requestedURL.length ) ;
    return memory ;
  }

  dynamic get json => hasBody ? jsonDecode(body) : null ;

  bool get hasBody => body != null && body.isNotEmpty ;

  String get bodyType => getResponseHeader('Content-Type') ;

  bool get isBodyTypeJSON {
    var type = bodyType;
    if (type == null) return false ;
    type = type.trim().toLowerCase() ;
    return type == 'application/json' || type == 'json' ;
  }

  JSONPaging get asJSONPaging {
    if ( isBodyTypeJSON ) {
      return JSONPaging.from( json ) ;
    }
    return null ;
  }

  String getResponseHeader(String headerKey) {
    if (_responseHeaderGetter == null) return null ;

    try {
      return _responseHeaderGetter(headerKey);
    }
    catch (e,s) {
      print("[HttpResponse] Can't access response header: $headerKey") ;
      print(e);
      print(s);
      return null ;
    }
  }

  @override
  String toString([bool withBody]) {
    withBody ??= false ;
    var infos = 'method: $method, requestedURL: $requestedURL, status: $status' ;
    if (withBody) infos += ', body: $body' ;
    return 'RESTResponse{$infos}';
  }

  @override
  int compareTo(HttpResponse other) {
    return instanceTime < other.instanceTime ? -1 : ( instanceTime == other.instanceTime ? 0 : 1 ) ;
  }

}

class HttpBody {

  static final HttpBody NULL = HttpBody(null,null) ;

  static String normalizeType(String bodyType) {
    if (bodyType == null) return null ;

    bodyType = bodyType.trim() ;
    if (bodyType.isEmpty) return null ;

    var bodyTypeLC = bodyType.toLowerCase() ;

    if ( bodyTypeLC == 'json' || bodyTypeLC.endsWith('/json') ) return 'application/json' ;
    if ( bodyTypeLC == 'jpeg' || bodyTypeLC.endsWith('/jpeg') ) return 'image/jpeg' ;
    if ( bodyTypeLC == 'png' || bodyTypeLC.endsWith('/png') ) return 'image/png' ;
    if (bodyTypeLC == 'text') return 'text/plain' ;
    if (bodyTypeLC == 'html') return 'text/html' ;

    return bodyType ;
  }

  ////////

  String _content ;
  String _contentType ;

  HttpBody(dynamic content, String type) {
    _contentType = normalizeType(type) ;

    if ( content is String ) {
      _content = content ;
    }
    else if ( isJSONType || (type == null && (content is Map || content is List)) ) {
      _content = json.encode(content) ;
    }
    else if ( content == null ) {
      _content = null ;
    }
    else {
      _content = '$content' ;
    }

  }

  String get content => _content;
  String get contentType => _contentType;

  bool get noContent => _content == null ;
  bool get noType => _contentType == null ;
  bool get isJSONType => _contentType != null && _contentType.endsWith('/json') ;

  bool get isNull => noContent && noType ;

}

typedef RequestHeadersBuilder = Map<String,String> Function(HttpClient client, String url) ;

typedef ResponseProcessor = void Function(HttpClient client, dynamic request, HttpResponse response) ;

typedef AuthorizationProvider = Future<Credential> Function( HttpClient client , HttpError lastError ) ;

class Authorization {
  final Credential _credential ;
  final AuthorizationProvider authorizationProvider ;

  Credential get credential => _credential ?? _resolvedCredential ;

  Authorization(this._credential, [this.authorizationProvider]) {
    if (_credential != null) {
      _resolvedCredential = _credential ;
    }
  }

  Authorization copy() {
    var authorization = Authorization(_credential, authorizationProvider);
    authorization._resolvedCredential = _resolvedCredential ;
    return authorization ;
  }

  Credential _resolvedCredential ;

  bool get isCredentialResolved => _resolvedCredential != null ;

  Future<Credential> resolveCredential(HttpClient client , HttpError lastError) async {
    if (_resolvedCredential != null) return _resolvedCredential ;

    if (_credential != null) {
      _resolvedCredential = _credential ;
      return _resolvedCredential ;
    }

    if (authorizationProvider != null) {
      var future = authorizationProvider(client, lastError);
      return future.then( (credential) {
        _resolvedCredential = credential ;
        return _resolvedCredential ;
      } );
    }

    return Future.value(null) ;
  }

  @override
  String toString() {
    return 'Authorization{credential: $credential, authorizationProvider: $authorizationProvider}';
  }
}

abstract class Credential {

  String get type ;

  bool get usesAuthorizationHeader ;

  String buildAuthorizationHeaderLine() {
    return null ;
  }

  String buildURL(String url) {
    return null ;
  }

  HttpBody buildBody(HttpBody body) {
    return null ;
  }

}

class BasicCredential extends Credential {
  final String username ;
  final String password ;

  BasicCredential(this.username, this.password);

  factory BasicCredential.base64(String base64) {
    var decodedBytes = Base64Codec.urlSafe().decode(base64) ;
    var decoded = String.fromCharCodes(decodedBytes) ;
    var idx = decoded.indexOf(':') ;

    if (idx < 0) {
      return BasicCredential(decoded, '') ;
    }

    var user = decoded.substring(0,idx) ;
    var pass = decoded.substring(idx+1) ;

    return BasicCredential(user, pass) ;
  }

  @override
  String get type => 'Basic' ;

  @override
  bool get usesAuthorizationHeader => true ;

  @override
  String buildAuthorizationHeaderLine() {
    var payload = '$username:$password' ;
    var encode = Base64Codec.urlSafe().encode(payload.codeUnits) ;
    return 'Basic $encode' ;
  }

}


class BearerCredential extends Credential {

  static dynamic findToken(Map json, String tokenKey) {
    if (json.isEmpty || tokenKey == null || tokenKey.isEmpty) return null ;

    var tokenKeys = tokenKey.split('/') ;

    dynamic token = findKeyValue(json, [ tokenKeys.removeAt(0) ] , true ) ;
    if (token == null) return null ;

    for (var k in tokenKeys) {
      if (token is Map) {
        token = findKeyValue(token, [ k ] , true ) ;
      }
      else if (token is List && isInt(k)) {
        var idx = parseInt(k) ;
        token = token[idx] ;
      }
      else {
        token = null ;
      }

      if (token == null) return null ;
    }

    if (token is String || token is num) {
      return token;
    }

    return null ;
  }

  final String token ;

  BearerCredential(this.token);

  static const List<String> _DEFAULT_EXTRA_TOKEN_KEYS = ['accessToken', 'accessToken/token'] ;

  factory BearerCredential.fromJSONToken( dynamic json , [String mainTokenKey = 'access_token', List<String> extraTokenKeys = _DEFAULT_EXTRA_TOKEN_KEYS ]) {
    if (json is Map) {
      var token = findKeyPathValue(json, mainTokenKey, isValidValue: isValidTokenValue) ;

      if (token == null && extraTokenKeys != null) {
        for (var key in extraTokenKeys) {
          token = findKeyPathValue(json, key, isValidValue: isValidTokenValue) ;
          if (token != null) break ;
        }
      }

      if (token != null) {
        var tokenStr = token.toString().trim() ;
        return tokenStr != null && tokenStr.isNotEmpty ? BearerCredential(tokenStr) : null ;
      }
    }

    return null ;
  }

  static bool isValidTokenValue(v) => v is String || v is num ;

  @override
  String get type => 'Bearer' ;

  @override
  bool get usesAuthorizationHeader => true ;

  @override
  String buildAuthorizationHeaderLine() {
    return 'Bearer $token' ;
  }
}

class QueryStringCredential extends Credential {
  final Map<String,String> fields ;

  QueryStringCredential(this.fields);

  @override
  String get type => 'queryString' ;

  @override
  bool get usesAuthorizationHeader => false ;

  @override
  String buildURL(String url) {
    return buildURLWithQueryParameters(url, fields) ;
  }

}

class JSONBodyCredential extends Credential {
  String _field ;
  final dynamic authorization ;

  JSONBodyCredential(String field, this.authorization) {
    if (field != null) {
      field = field.trim() ;
      _field = field.isNotEmpty ? field : null ;
    }
  }

  String get field => _field;

  @override
  String get type => 'jsonbody';

  @override
  bool get usesAuthorizationHeader => false;

  @override
  String buildAuthorizationHeaderLine() {
    return null;
  }

  @override
  String buildURL(String url) {
    return url ;
  }

  @override
  HttpBody buildBody(HttpBody body) {
    if (body == null || body.isNull) {
      return buildJSONAuthorizationBody(null);
    }
    else if ( body.isJSONType ) {
      return buildJSONAuthorizationBody( body.content ) ;
    }
    else {
      return body ;
    }
  }

  HttpBody buildJSONAuthorizationBody(String body) {
    return HttpBody( buildJSONAuthorizationBodyJSON(body) , 'application/json' ) ;
  }

  String buildJSONAuthorizationBodyJSON(String body) {
    if ( body == null ) {
      if (field == null || field.isEmpty) {
        return json.encode( authorization ) ;
      }
      else {
        return json.encode( { '$field': authorization } ) ;
      }
    }

    var bodyJson = json.decode(body) ;

    if (field == null || field.isEmpty) {
      if ( authorization is Map ) {
        if ( bodyJson is Map ) {
          bodyJson.addAll(authorization) ;
        }
        else {
          throw StateError("No specified field for authorization. Can't add authorization to current body! Current body is not a Map to receive a Map authorization.") ;
        }
      }
      else if ( authorization is List ) {
        if ( bodyJson is List ) {
          bodyJson.addAll(authorization) ;
        }
        else {
          throw StateError("No specified field for authorization. Can't add authorization to current body! Current body is not a List to receive a List authorization.") ;
        }
      }
      else {
        throw StateError("No specified field for authorization. Can't add authorization to current body! authorization is not a Map or List to add to any type of body.") ;
      }
    }
    else {
      bodyJson[ field ] = authorization ;
    }

    return json.encode(bodyJson) ;
  }

}

String buildURLWithQueryParameters(String url, Map<String, String> fields) {
  if ( fields == null || fields.isEmpty ) return url ;

  var uri = Uri.parse(url) ;

  Map<String, String> queryParameters ;

  if ( uri.query == null || uri.query.isEmpty ) {
    queryParameters = Map.from(fields) ;
  }
  else {
    queryParameters = uri.queryParameters ?? {} ;
    queryParameters = Map.from(queryParameters) ;
    queryParameters.addAll( fields ) ;
  }

  return Uri( scheme: uri.scheme, userInfo: uri.userInfo, host: uri.host, port: uri.port, path: Uri.decodeComponent( uri.path ) , queryParameters: queryParameters , fragment: uri.fragment ).toString() ;
}

enum HttpMethod {
  GET,
  OPTIONS,
  POST,
  PUT,
  DELETE,
  PATCH
}


HttpMethod getHttpMethod(String method, [HttpMethod def]) {
  if (method == null) return def ;
  method = method.trim().toUpperCase() ;
  if (method.isEmpty) return def ;

  switch (method) {
    case 'GET': return HttpMethod.GET ;
    case 'OPTIONS': return HttpMethod.OPTIONS ;
    case 'POST': return HttpMethod.POST ;
    case 'PUT': return HttpMethod.PUT ;
    case 'DELETE': return HttpMethod.DELETE ;
    case 'PATCH': return HttpMethod.PATCH ;
    default: return def ;
  }
}

class HttpRequest {
  final String method ;
  final String url ;
  final String requestURL ;
  final Map<String,String> queryParameters ;
  final Authorization authorization ;

  final bool withCredentials ;
  final String responseType ;
  final String mimeType ;
  final Map<String, String> requestHeaders ;
  final dynamic sendData ;

  int _retries = 0 ;

  HttpRequest(this.method, this.url, this.requestURL, { this.queryParameters, this.authorization, this.withCredentials, this.responseType, this.mimeType, this.requestHeaders, this.sendData });

  HttpRequest copy( [HttpClient client , Authorization authorization] ) {
    if ( authorization == null || authorization == this.authorization ) return this ;

    var requestHeaders = client.clientRequester.buildRequestHeaders(client, url, authorization, sendData, headerContentType, headerAccept) ;

    // ignore: omit_local_variable_types
    Map<String,String> queryParameters = this.queryParameters != null ? Map.from( this.queryParameters ) : null ;
    var requestURL = client.clientRequester.buildRequestURL(client, url, authorization, queryParameters) ;

    var copy = HttpRequest(method, url, requestURL, queryParameters: queryParameters, authorization: authorization, withCredentials: withCredentials, responseType: responseType, mimeType: mimeType, requestHeaders: requestHeaders, sendData: sendData);
    copy._retries = _retries ;

    return copy ;
  }

  String get headerAccept => requestHeaders != null ? requestHeaders['Accept'] : null ;
  String get headerContentType => requestHeaders != null ? requestHeaders['Content-Type'] : null ;

  int get retries => _retries;

  void incrementRetries() {
    _retries++ ;
  }

  @override
  String toString() {
    return 'HttpRequest{method: $method, url: $url, requestURL: $requestURL, retries: $_retries, queryParameters: $queryParameters, authorization: $authorization, withCredentials: $withCredentials, responseType: $responseType, mimeType: $mimeType, requestHeaders: $requestHeaders, sendData: $sendData}';
  }
}

abstract class HttpClientRequester {

  Future<HttpResponse> request(HttpClient client, HttpMethod method, String url, {Authorization authorization, Map<String,String> queryParameters, dynamic body, String contentType, String accept}) {
    switch (method) {
      case HttpMethod.GET: return requestGET(client, url, authorization: authorization) ;
      case HttpMethod.OPTIONS: return requestOPTIONS(client, url, authorization: authorization) ;
      case HttpMethod.POST: return requestPOST(client, url, authorization: authorization, queryParameters: queryParameters, body: body, contentType: contentType, accept: accept) ;
      case HttpMethod.PUT: return requestPUT(client, url, authorization: authorization, body: body, contentType: contentType, accept: accept) ;

      default: throw StateError("Can't handle method: ${ EnumToString.parse(method) }") ;
    }
  }

  bool _withCredentials(HttpClient client, Authorization authorization) {
    if ( client.crossSiteWithCredentials != null ) {
      return client.crossSiteWithCredentials ;
    }

    if ( authorization != null && authorization.credential != null && authorization.credential.usesAuthorizationHeader ) {
      return true ;
    }
    else {
      return false;
    }
  }

  Future<HttpResponse> requestGET(HttpClient client, String url, { Authorization authorization, Map<String,String> queryParameters }) {
    return doHttpRequest(
        client,
        HttpRequest('GET' , url, buildRequestURL(client, url, authorization, queryParameters),
            authorization: authorization,
            queryParameters: queryParameters,
            withCredentials: _withCredentials(client, authorization) ,
            requestHeaders: buildRequestHeaders(client, url, authorization)
        )
        , client.logRequests
    ) ;
  }

  Future<HttpResponse> requestOPTIONS(HttpClient client, String url, { Authorization authorization , Map<String,String> queryParameters } ) {
    return doHttpRequest(
        client,
        HttpRequest('OPTIONS' , url, buildRequestURL(client, url, authorization, queryParameters),
            authorization: authorization,
            queryParameters: queryParameters,
            withCredentials: _withCredentials(client, authorization) ,
            requestHeaders: buildRequestHeaders(client, url, authorization)
        )
        , client.logRequests
    ) ;
  }

  Future<HttpResponse> requestPOST(HttpClient client, String url, { Authorization authorization, Map<String,String> queryParameters, dynamic body, String contentType, String accept }) {
    var httpBody = HttpBody(body, contentType);
    var requestBody = buildRequestBody(client, httpBody, authorization) ;

    if (queryParameters != null && queryParameters.isNotEmpty && requestBody.isNull) {
      var requestHeaders = buildRequestHeaders(client, url, authorization, requestBody.content, requestBody.contentType, accept);
      requestHeaders ??= {} ;

      var formData = buildPOSTFormData(queryParameters, requestHeaders);
      if (requestHeaders.isEmpty) requestHeaders = null ;

      return doHttpRequest(
          client,
          HttpRequest('POST', url, buildRequestURL(client, url, authorization),
              authorization: authorization,
              queryParameters: queryParameters,
              withCredentials: _withCredentials(client, authorization) ,
              requestHeaders: requestHeaders ,
              sendData: formData
          )
          , client.logRequests
      );
    }
    else {
      return doHttpRequest(
          client,
          HttpRequest('POST' , url, buildRequestURL(client, url, authorization, queryParameters),
              authorization: authorization,
              queryParameters: queryParameters,
              withCredentials: _withCredentials(client, authorization) ,
              requestHeaders: buildRequestHeaders(client, url, authorization, requestBody.content, requestBody.contentType, accept),
              sendData: requestBody.content
          )
          , client.logRequests
      ) ;
    }
  }

  Future<HttpResponse> requestPUT(HttpClient client, String url, { Authorization authorization, dynamic body, String contentType, String accept }) {
    var httpBody = HttpBody(body, contentType);
    var requestBody = buildRequestBody(client, httpBody, authorization) ;

    return doHttpRequest(
        client,
        HttpRequest('PUT' , url, buildRequestURL(client, url, authorization),
            authorization: authorization,
            withCredentials: _withCredentials(client, authorization) ,
            requestHeaders: buildRequestHeaders(client, url, authorization, requestBody.content, requestBody.contentType, accept),
            sendData: requestBody.content
        )
        , client.logRequests
    ) ;
  }

  /////////////////////////////////////////////////////////////////////////////////////////

  Future<HttpResponse> doHttpRequest( HttpClient client, HttpRequest request , bool log ) ;

  String buildPOSTFormData(Map<String, String> data, [Map<String, String> requestHeaders]) {
    var formData = buildQueryString(data) ;

    if (requestHeaders != null) {
      requestHeaders.putIfAbsent('Content-Type', () => 'application/x-www-form-urlencoded; charset=UTF-8') ;
    }

    return formData ;
  }

  String buildQueryString(Map<String, String> data) {
    var parts = [];
    data.forEach((key, value) {
      var keyValue = '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}' ;
      parts.add( keyValue);
    });

    var queryString = parts.join('&');
    return queryString ;
  }

  Map<String, String> buildRequestHeaders(HttpClient client, String url, [Authorization authorization, dynamic body, String contentType, String accept]) {
    var header = client.buildRequestHeaders(url) ;

    if (contentType != null) {
      header ??= {};
      header['Content-Type'] = contentType ;
    }

    if (accept != null) {
      header ??= {};
      header['Accept'] = accept ;
    }

    if ( authorization != null && authorization.credential != null && authorization.credential.usesAuthorizationHeader) {
      header ??= {};

      var authorizationHeaderLine = authorization.credential.buildAuthorizationHeaderLine();
      if (authorizationHeaderLine != null) {
        header['Authorization'] = authorizationHeaderLine;
      }
    }

    return header ;
  }

  String buildRequestURL(HttpClient client, String url, [Authorization authorization, Map<String,String> queryParameters]) {
    if (queryParameters != null && queryParameters.isNotEmpty) {
      url = buildURLWithQueryParameters(url, queryParameters) ;
    }

    if ( authorization != null && authorization.credential != null ) {
      var authorizationURL = authorization.credential.buildURL(url) ;
      if (authorizationURL != null) return authorizationURL ;
    }

    return url ;
  }

  HttpBody buildRequestBody(HttpClient client, HttpBody httpBody, Authorization authorization) {
    if ( authorization != null && authorization.credential != null ) {
      var jsonBody = authorization.credential.buildBody(httpBody) ;
      if (jsonBody != null) return jsonBody ;
    }

    return httpBody ?? HttpBody.NULL ;
  }

}

class HttpClient {

  String baseURL ;

  HttpClientRequester _clientRequester ;

  HttpClientRequester get clientRequester => _clientRequester;

  static int _idCounter = 0 ;
  int _id ;

  HttpClient(String baseURL, [HttpClientRequester clientRequester]) {
    _id = ++_idCounter ;

    if (baseURL.endsWith('/')) baseURL = baseURL.substring(0,baseURL.length-1) ;
    this.baseURL = baseURL ;

    _clientRequester = clientRequester ?? createHttpClientRequester() ;
  }


  @override
  String toString() {
    return 'HttpClient{id: $_id, baseURL: $baseURL, authorization: $authorization, crossSiteWithCredentials: $crossSiteWithCredentials, logJSON: $logJSON, _clientRequester: $_clientRequester}';
  }

  int get id => _id;

  bool isLocalhost() {
    return baseURL.startsWith(RegExp('https?://localhost')) ;
  }

  Future<dynamic> requestJSON(HttpMethod method, String path, { Credential authorization, Map<String,String> queryParameters, dynamic body, String contentType, String accept } ) async {
    return request(method, path, authorization: authorization, queryParameters: queryParameters, body: body, contentType: contentType, accept: accept).then((r) => _jsonDecode(r.body)) ;
  }

  Future<dynamic> getJSON(String path, { Credential authorization, Map<String,String> parameters } ) async {
    return get(path, authorization: authorization, parameters: parameters).then((r) => _jsonDecode(r.body)) ;
  }

  Future<dynamic> optionsJSON(String path, { Credential authorization, Map<String,String> parameters } ) async {
    return options(path, authorization: authorization, parameters: parameters).then((r) => _jsonDecode(r.body)) ;
  }

  Future<dynamic> postJSON(String path,  { Credential authorization, Map<String,String> parameters , dynamic body , String contentType }) async {
    return post(path, authorization: authorization, parameters: parameters, body: body, contentType: contentType).then((r) => _jsonDecode(r.body)) ;
  }

  Future<dynamic> putJSON(String path,  { Credential authorization, dynamic body , String contentType }) async {
    return put(path, authorization: authorization, body: body, contentType: contentType).then((r) => _jsonDecode(r.body)) ;
  }

  bool crossSiteWithCredentials ;

  Credential authorization ;

  String _responseHeaderWithToken ;
  String get responseHeaderWithToken => _responseHeaderWithToken;

  HttpClient autoChangeAuthorizationToBearerToken(String responseHeaderWithToken) {
    _responseHeaderWithToken = responseHeaderWithToken ;
    return this ;
  }

  AuthorizationProvider authorizationProvider ;

  bool logRequests = false ;

  bool logJSON = false ;

  dynamic _jsonDecode(String s) {
    if (logJSON) _logJSON(s);

    return jsonDecode(s) ;
  }

  void _logJSON(String json) {
    var now = DateTime.now();
    print('$now> HttpClient> $json');
  }

  Future<Credential> _requestAuthorizationResolvingFuture ;
  Authorization _requestAuthorizationResolving ;

  dynamic get requestAuthorizationResolvingFuture => _requestAuthorizationResolvingFuture ;
  dynamic get requestAuthorizationResolving => _requestAuthorizationResolving ;

  Authorization _requestAuthorizationResolved ;
  Authorization get resolvedAuthorization => _requestAuthorizationResolved ;

  Future<Authorization> _buildRequestAuthorization(Credential credential) async {
    if ( credential != null ) {
      return Authorization( credential , authorizationProvider ) ;
    }
    else if (authorization == null && authorizationProvider == null) {
      return Future.value(null);
    }
    else {
      if ( _requestAuthorizationResolved != null ) {
        return _requestAuthorizationResolved ;
      }

      var requestAuthorizationResolvingFuture = _requestAuthorizationResolvingFuture ;
      if ( requestAuthorizationResolvingFuture != null ) {
        return requestAuthorizationResolvingFuture.then( (c) {
          return _requestAuthorizationResolved ?? _requestAuthorizationResolving ;
        } ) ;
      }

      var authorizationResolving = Authorization( authorization , authorizationProvider ) ;

      var resolvingCredentialFuture = authorizationResolving.resolveCredential(this, null);
      _requestAuthorizationResolving = authorizationResolving ;
      _requestAuthorizationResolvingFuture = resolvingCredentialFuture ;

      return resolvingCredentialFuture.then( (c) {
        if ( authorizationResolving.isCredentialResolved ) {
          _requestAuthorizationResolved = authorizationResolving ;
          _requestAuthorizationResolvingFuture = null ;
          _requestAuthorizationResolving = null ;
          return _requestAuthorizationResolved ;
        }
        else {
          _requestAuthorizationResolved = null ;
          _requestAuthorizationResolvingFuture = null ;
          _requestAuthorizationResolving = null ;
          return null ;
        }
      } ) ;
    }
  }

  Future<HttpResponse> request(HttpMethod method, String path, { bool fullPath, Credential authorization, Map<String,String> queryParameters, dynamic body, String contentType, String accept } ) async {
    var url = buildMethodRequestURL(method, path, fullPath, queryParameters);
    return requestURL(method, url, authorization: authorization, queryParameters: queryParameters, body: body, contentType: contentType, accept: accept);
  }

  String buildMethodRequestURL(HttpMethod method, String path, bool fullPath, Map<String, String> queryParameters) {
    var urlParameters = method == HttpMethod.GET || method == HttpMethod.OPTIONS ;
    var url = urlParameters ? _buildURL(path, fullPath, queryParameters) :  _buildURL(path, fullPath) ;
    return url;
  }

  Future<HttpResponse> requestURL(HttpMethod method, String url, { Credential authorization, Map<String,String> queryParameters, dynamic body, String contentType, String accept } ) async {
    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.request(this, method, url, authorization: requestAuthorization, queryParameters: queryParameters, body: body, contentType: contentType, accept: accept);
  }

  Future<HttpResponse> get(String path, { bool fullPath, Credential authorization, Map<String,String> parameters } ) async {
    var url = _buildURL(path, fullPath, parameters);
    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestGET( this, url, authorization: requestAuthorization );
  }

  Future<HttpResponse> options(String path, { bool fullPath, Credential authorization, Map<String,String> parameters } ) async {
    var url = _buildURL(path, fullPath, parameters);
    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestOPTIONS(this, url, authorization: requestAuthorization);
  }

  Future<HttpResponse> post(String path, { bool fullPath, Credential authorization, Map<String,String> parameters , dynamic body , String contentType , String accept}) async {
    var url = _buildURL(path, fullPath);

    var uri = Uri.parse(url);

    if (uri.queryParameters != null && uri.queryParameters.isNotEmpty) {
      if (parameters != null && parameters.isNotEmpty) {
        uri.queryParameters.forEach((k,v) => parameters.putIfAbsent(k, () => v) ) ;
      }
      else {
        parameters = uri.queryParameters ;
      }

      url = _removeURIQueryParameters(uri).toString() ;
    }

    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestPOST(this, url, authorization: requestAuthorization, queryParameters: parameters, body: body, contentType: contentType, accept: accept);
  }

  Future<HttpResponse> put(String path, { bool fullPath, Credential authorization, dynamic body , String contentType , String accept}) async {
    var url = _buildURL(path, fullPath);
    var requestAuthorization = await _buildRequestAuthorization(authorization);
    return _clientRequester.requestPUT(this, url, authorization: requestAuthorization, body: body, contentType: contentType, accept: accept);
  }

  Uri _removeURIQueryParameters(var uri) {
    if ( uri.schema.toLowerCase() == 'https' ) {
      return Uri.https(uri.authority,  Uri.decodeComponent( uri.path ) ) ;
    }
    else {
      return Uri.http(uri.authority, Uri.decodeComponent( uri.path ) ) ;
    }
  }

  String buildRequestURL(String path, bool fullPath, [Map<String,String> queryParameters]) {
    return _buildURL(path, fullPath, queryParameters) ;
  }

  String _buildURL(String path, bool fullPath, [Map<String,String> queryParameters]) {
    if (path == null) {
      if (queryParameters == null || queryParameters.isEmpty) {
        return baseURL ;
      }
      else {
        return _buildURLWithParameters(baseURL, queryParameters) ;
      }
    }

    if ( !path.startsWith('/') ) path = '/$path' ;

    var url ;

    if (fullPath != null && fullPath) {
      var uri = Uri.parse(baseURL);

      var uri2 ;
      if ( uri.scheme.toLowerCase() == 'https' ) {
        uri2 = Uri.https(uri.authority, path) ;
      }
      else {
        uri2 = Uri.http(uri.authority, path) ;
      }

      url = uri2.toString() ;
    }
    else {
      url = '$baseURL$path' ;
    }

    return _buildURLWithParameters(url, queryParameters) ;
  }


  String _buildURLWithParameters(String url, Map<String,String> queryParameters) {
    var uri = Uri.parse(url);

    var uriParameters = uri.queryParameters ;

    if ( uriParameters != null && uriParameters.isNotEmpty ) {
      if (queryParameters == null || queryParameters.isEmpty) {
        queryParameters = uriParameters ;
      }
      else {
        uriParameters.forEach( (k,v) => queryParameters.putIfAbsent(k, () => v) ) ;
      }
    }

    var uri2 ;

    if ( uri.scheme.toLowerCase() == 'https' ) {
      uri2 = Uri.https(uri.authority, Uri.decodeComponent( uri.path ) , queryParameters) ;
    }
    else {
      uri2 = Uri.http(uri.authority, Uri.decodeComponent( uri.path ) , queryParameters) ;
    }

    var url2 = uri2.toString() ;

    print('Request URL: $url2') ;

    return url2 ;
  }


  ResponseProcessor responseProcessor ;

  RequestHeadersBuilder requestHeadersBuilder ;

  Map<String, String> buildRequestHeaders(String url) {
    if (requestHeadersBuilder == null) return null ;
    return requestHeadersBuilder(this, url) ;
  }

}

////////////////////////////////////////

typedef SimulateResponse = String Function(String url, Map<String, String> queryParameters);

class HttpClientRequesterSimulation extends HttpClientRequester {

  /// GET

  final Map<RegExp, SimulateResponse> _getPatterns = {} ;

  void replyGET(RegExp urlPattern, String response) {
    simulateGET(urlPattern , (u,p) => response) ;
  }

  void simulateGET(RegExp urlPattern, SimulateResponse response) {
    _getPatterns[urlPattern] = response ;
  }

  /// OPTIONS

  final Map<RegExp, SimulateResponse> _optionsPatterns = {} ;

  void replyOPTIONS(RegExp urlPattern, String response) {
    simulateOPTIONS(urlPattern , (u,p) => response) ;
  }

  void simulateOPTIONS(RegExp urlPattern, SimulateResponse response) {
    _optionsPatterns[urlPattern] = response ;
  }

  /// POST

  final Map<RegExp, SimulateResponse> _postPatterns = {} ;

  void replyPOST(RegExp urlPattern, String response) {
    simulatePOST(urlPattern , (u,p) => response) ;
  }

  void simulatePOST(RegExp urlPattern, SimulateResponse response) {
    _postPatterns[urlPattern] = response ;
  }

  /// PUT

  final Map<RegExp, SimulateResponse> _putPatterns = {} ;

  void replyPUT(RegExp urlPattern, String response) {
    simulatePUT(urlPattern , (u,p) => response) ;
  }

  void simulatePUT(RegExp urlPattern, SimulateResponse response) {
    _putPatterns[urlPattern] = response ;
  }

  /// ANY

  final Map<RegExp, SimulateResponse> _anyPatterns = {} ;

  void replyANY(RegExp urlPattern, String response) {
    simulateANY(urlPattern , (u,p) => response) ;
  }

  void simulateANY(RegExp urlPattern, SimulateResponse response) {
    _anyPatterns[urlPattern] = response ;
  }

  ////////////

  Map<RegExp, SimulateResponse> methodSimulationPatterns(String method) {

    switch(method) {
      case 'GET': return _getPatterns ?? _anyPatterns ;
      case 'OPTIONS': return _optionsPatterns ?? _anyPatterns ;
      case 'PUT': return _putPatterns ?? _anyPatterns ;
      case 'POST': return _postPatterns ?? _anyPatterns ;
      default: return null ;
    }

  }

  SimulateResponse _findResponse(String url, Map<RegExp, SimulateResponse> patterns ) {
    if ( patterns == null || patterns.isEmpty ) return null ;

    for (var p in patterns.keys) {
      if ( p.hasMatch(url) ) {
        return patterns[p] ;
      }
    }
    return null ;
  }

  //////////////////////

  @override
  Future<HttpResponse> doHttpRequest(HttpClient client, HttpRequest request, bool log ) {
    var methodPatterns = methodSimulationPatterns(request.method) ;
    return _requestSimulated(client, request.method, request.requestURL, methodPatterns, request.queryParameters) ;
  }

  Future<HttpResponse> _requestSimulated(HttpClient client, String method, String url, Map<RegExp, SimulateResponse> methodPatterns, Map<String, String> queryParameters) {
    var resp = _findResponse(url, methodPatterns) ?? _findResponse(url, _anyPatterns) ;

    if (resp == null) {
      return Future.error('No simulated response[$method]') ;
    }

    var respVal = resp(url, queryParameters) ;

    var restResponse = HttpResponse(method, url, url, 200, respVal) ;

    return Future.value(restResponse) ;
  }

}

Converter<List<int>, String> contentTypeToDecoder(String mimeType, [String charset]) {
  if ( charset != null ) {
    charset = charset.trim().toLowerCase() ;

    if (charset == 'utf8' || charset == 'utf-8') {
      return utf8.decoder ;
    }
    else if (charset == 'latin1' || charset == 'latin-1' || charset == 'iso-8859-1') {
      return latin1.decoder ;
    }
  }

  if (mimeType != null) {
    mimeType = mimeType.trim().toLowerCase() ;

    if ( mimeType == 'application/json' ) {
      return utf8.decoder ;
    }
    else if ( mimeType == 'application/x-www-form-urlencoded' ) {
      return latin1.decoder ;
    }
  }

  return latin1.decoder ;
}

class HttpRequester {

  final MapProperties config ;
  final MapProperties properties ;
  HttpCache httpCache ;

  String _scheme ;
  String _host ;
  HttpMethod _httpMethod ;
  String _path ;
  String _bodyType ;
  String _body ;
  String _responseType ;

  HttpRequester(this.config , [MapProperties properties, this.httpCache]) :
        properties = properties ?? {}
  {

    var runtimeUri = getHttpClientRuntimeUri() ;

    var schemeType = config.findPropertyAsStringTrimLC( ['scheme','protocol','type'] , 'http') ;
    var secure = config.findPropertyAsBool( ['scure','ssl','https'] , false ) ;

    var host = config.getPropertyAsStringTrimLC('host') ;
    var method = config.findPropertyAsStringTrimLC( ['method' , 'htttp_method', 'htttpMethod'] ) ;

    var path = config.getPropertyAsString('path', '/') ;

    var bodyType = config.findPropertyAsStringTrimLC( ['body_type', 'bodyType', 'content_type', 'content-type', 'contentType'] );
    var body = config.getPropertyAsStringTrimLC( 'body' );

    var responseType = config.findPropertyAsStringTrimLC( ['response_type', 'responseType'] );

    /////

    var scheme = schemeType == 'https' ? 'https' : ( schemeType == 'http' ? 'http' : runtimeUri.scheme ) ;

    if (secure) {
      scheme = 'https' ;
    }

    if (host == null) {
      host = '${ runtimeUri.host }:${ runtimeUri.port }' ;
    }
    else if ( RegExp(r'^:?\d+$').hasMatch(host) ) {
      var port = host ;
      if ( port.startsWith(':') ) port = port.substring(1) ;
      host = '${ runtimeUri.host }:$port' ;
    }

    /////

    var httpMethod = getHttpMethod(method, HttpMethod.GET) ;

    /////

    var pathBuilt = '/' ;

    if (path != null) {
      pathBuilt = path.contains('{{') ? buildStringPattern(path, properties.toStringProperties()) : path ;
    }

    /////

    var bodyBuilt ;

    if (body != null) {
      bodyBuilt = body.contains('{{') ? buildStringPattern(body, properties.toStringProperties()) : body ;
    }

    /////

    _host = host ;
    _scheme = scheme ;
    _httpMethod = httpMethod ;
    _path = pathBuilt ;
    _responseType = responseType ;
    _bodyType = bodyType ;
    _body = bodyBuilt ;

  }

  String get scheme => _scheme;
  String get host => _host;
  HttpMethod get httpMethod => _httpMethod;
  String get path => _path;
  String get bodyType => _bodyType;
  String get body => _body;
  String get responseType => _responseType;

  String get baseURL => '$_scheme://$_host/' ;

  HttpClient _httpClient ;

  HttpClient get httpClient {
    _httpClient ??= HttpClient( baseURL );
    return _httpClient ;
  }

  Future<dynamic> doRequest() {
    return doRequestWithClient( httpClient ) ;
  }

  Future<dynamic> doRequestWithClient( HttpClient httpClient ) async {

    HttpResponse httpResponse ;
    if ( httpCache != null ) {
      httpResponse = await httpCache.request( httpClient , httpMethod, path, body: _body, contentType: bodyType) ;
    }
    else {
      httpResponse = await httpClient.request( httpMethod, path, body: _body, contentType: bodyType) ;
    }

    return _processResponse(httpResponse, httpClient);
  }

  dynamic _processResponse(HttpResponse httpResponse, HttpClient client) {
    if ( !httpResponse.isOK ) return null ;

    if ( _responseType == 'json' ) {
      return httpResponse.json ;
    }
    else if ( _responseType == 'jsonpaging' || _responseType == 'json_paging' ) {
      return _asJSONPaging(client, httpResponse) ;
    }

    if ( httpResponse.isBodyTypeJSON ) {
      var asJSONPaging = _asJSONPaging(client, httpResponse) ;
      return asJSONPaging ?? httpResponse.json ;
    }

    return httpResponse.body ;
  }

  JSONPaging _asJSONPaging( HttpClient client, HttpResponse httpResponse ) {
    var paging = httpResponse.asJSONPaging ;
    if (paging == null) return null ;

    paging.pagingRequester = (page) async {
      var method = getHttpMethod( httpResponse.method ) ;
      var url = paging.pagingRequestURL(httpResponse.requestedURL, page) ;
      var httpResponse2 = await client.requestURL( method , url.toString() ) ;
      return _asJSONPaging(client, httpResponse2) ;
    };

    return paging ;
  }

}