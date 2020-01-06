import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enum_to_string/enum_to_string.dart';

import 'http_client_none.dart'
if (dart.library.html) "http_client_browser.dart"
if (dart.library.io) "http_client_io.dart" ;

///////////////////////////////////////////////////////

typedef String ResponseHeaderGetter(String headerKey) ;


class HttpStatus {

  final String requestedURL ;
  final int status ;

  HttpStatus(this.requestedURL, this.status);

  /////

  bool get isOK => isStatusSuccessful ;
  bool get isError => isStatusError ;

  bool get isStatusSuccessful => isStatusInRange(200, 299) ;

  bool get isStatusNotFound => isStatus(404) ;

  bool get isStatusUnauthenticated => isStatus(401) ;

  bool get isStatusNetworkError => this.status == null || this.status <= 0 ;

  bool get isStatusServerError => isStatusInRange(500, 599) ;

  bool get isStatusAccessError => isStatusInRange(405 , 418) || isStatusInList([ 400 , 403 , 431 , 451 ])  ;

  bool get isStatusError => isStatusNetworkError || isStatusServerError || isStatusAccessError ;

  /////

  bool isStatus( int status ) {
    return this.status != null && this.status == status ;
  }

  bool isStatusInRange( int statusInit , int statusEnd ) {
    return this.status != null && this.status >= statusInit && this.status <= statusEnd ;
  }

  bool isStatusInList( List<int> statusList ) {
    return this.status != null && ( statusList.firstWhere( (id) => id == this.status , orElse: () => null ) != null ) ;
  }

}


class HttpError extends HttpStatus {

  final String message ;
  final dynamic error ;

  HttpError(String requestedURL, int status, this.message, this.error) : super(requestedURL, status) ;

  @override
  String toString() {
    return 'RESTError{requestedURL: $requestedURL, status: $status, message: $message, error: $error}';
  }

}

class HttpResponse extends HttpStatus {
  final String method ;
  final String body ;
  final ResponseHeaderGetter _responseHeaderGetter ;
  final dynamic request ;

  HttpResponse(this.method, String requestedURL, int status, this.body, [this._responseHeaderGetter, this.request]) : super(requestedURL, status) ;

  dynamic get json => hasBody ? jsonDecode(body) : null ;

  bool get hasBody => body != null && body.isNotEmpty ;

  String getResponseHeader(String headerKey) {
    if (_responseHeaderGetter == null) return null ;
    return _responseHeaderGetter(headerKey) ;
  }

  @override
  String toString() {
    return 'RESTResponse{method: $method, requestedURL: $requestedURL, status: $status, body: $body}';
  }
}

typedef Map<String,String> RequestHeadersBuilder(HttpClient client, String url) ;

typedef void ResponseProcessor(HttpClient client, dynamic request, HttpResponse response) ;

typedef Future<Credential> AuthorizationProvider( HttpClient client , HttpError lastError ) ;

class Authorization {
  final Credential _credential ;
  final AuthorizationProvider authorizationProvider ;

  Credential get credential => _credential ?? _resolvedCredential ;

  Authorization(this._credential, [this.authorizationProvider]) {
    if (this._credential != null) {
      _resolvedCredential = this._credential ;
    }
  }

  Authorization copy() {
    var authorization = Authorization(this._credential, this.authorizationProvider);
    authorization._resolvedCredential = this._resolvedCredential ;
    return authorization ;
  }

  Credential _resolvedCredential ;

  bool get isCredentialResolved => _resolvedCredential != null ;

  Future<Credential> resolveCredential(HttpClient client , HttpError lastError) async {
    if (_resolvedCredential != null) return _resolvedCredential ;

    if (this._credential != null) {
      _resolvedCredential = this._credential ;
      return _resolvedCredential ;
    }

    if (this.authorizationProvider != null) {
      var future = this.authorizationProvider(client, lastError);
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

  String buildHeaderLine() ;

  String buildURL(String url) {
    return null ;
  }

}

class BasicCredential extends Credential {
  final String username ;
  final String password ;

  BasicCredential(this.username, this.password);

  factory BasicCredential.base64(String base64) {
    Uint8List decodedBytes = Base64Codec.urlSafe().decode(base64) ;
    String decoded = new String.fromCharCodes(decodedBytes) ;
    int idx = decoded.indexOf(':') ;

    if (idx < 0) {
      return BasicCredential(decoded, '') ;
    }

    String user = decoded.substring(0,idx) ;
    String pass = decoded.substring(idx+1) ;

    return BasicCredential(user, pass) ;
  }

  String get type => "Basic" ;

  bool get usesAuthorizationHeader => true ;

  String buildHeaderLine() {
    String payload = "$username:$password" ;
    var encode = Base64Codec.urlSafe().encode(payload.codeUnits) ;
    return "Basic $encode" ;
  }
}


class BearerCredential extends Credential {
  final String token ;

  BearerCredential(this.token);

  String get type => "Bearer" ;

  bool get usesAuthorizationHeader => true ;

  String buildHeaderLine() {
    return "Bearer $token" ;
  }
}

class QueryStringCredential extends Credential {
  final Map<String,String> fields ;

  QueryStringCredential(this.fields);

  @override
  String get type => "queryString" ;

  bool get usesAuthorizationHeader => false ;

  @override
  String buildHeaderLine() {
    return null;
  }

  @override
  String buildURL(String url) {
    return buildURLWithQueryParameters(url, this.fields) ;
  }

}

String buildURLWithQueryParameters(String url, Map<String, String> fields) {
  if ( fields == null || fields.isEmpty ) return url ;

  Uri uri = Uri.parse(url) ;

  Map<String, String> queryParameters ;

  if ( uri.query == null || uri.query.isEmpty ) {
    queryParameters = Map.from(fields) ;
  }
  else {
    queryParameters = uri.queryParameters ?? {} ;
    queryParameters = Map.from(queryParameters) ;
    queryParameters.addAll( fields ) ;
  }

  return Uri( scheme: uri.scheme, userInfo: uri.userInfo, host: uri.host, port: uri.port, path: uri.path, queryParameters: queryParameters , fragment: uri.fragment ).toString() ;
}

enum HttpMethod {
  GET,
  OPTIONS,
  POST,
  PUT,
  DELETE,
  PATCH
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

  HttpRequest(this.method, this.url, this.requestURL, { this.queryParameters, this.authorization, this.withCredentials, this.responseType, this.mimeType, this.requestHeaders, this.sendData });

  HttpRequest copy( [HttpClient client , Authorization authorization] ) {
    if ( authorization == null || authorization == this.authorization ) return this ;

    Map<String, String> requestHeaders = client.clientRequester.buildRequestHeaders(client, url, authorization, this.sendData, this.headerContentType, this.headerAccept) ;

    Map<String,String> queryParameters = this.queryParameters != null ? Map.from( this.queryParameters ) : null ;
    String requestURL = client.clientRequester.buildRequestURL(client, this.url, authorization, queryParameters) ;

    return HttpRequest(this.method, this.url, requestURL, queryParameters: queryParameters, authorization: authorization, withCredentials: this.withCredentials, responseType: this.responseType, mimeType: this.mimeType, requestHeaders: requestHeaders, sendData: this.sendData) ;
  }

  String get headerAccept => requestHeaders != null ? requestHeaders['Accept'] : null ;
  String get headerContentType => requestHeaders != null ? requestHeaders['Content-Type'] : null ;

}

abstract class HttpClientRequester {

  Future<HttpResponse> request(HttpClient client, HttpMethod method, String url, {Authorization authorization, Map<String,String> queryParameters, String body, String contentType, String accept}) {
    switch (method) {
      case HttpMethod.GET: return requestGET(client, url, authorization: authorization) ;
      case HttpMethod.OPTIONS: return requestOPTIONS(client, url, authorization: authorization) ;
      case HttpMethod.POST: return requestPOST(client, url, authorization: authorization, queryParameters: queryParameters, body: body, contentType: contentType, accept: accept) ;
      case HttpMethod.PUT: return requestPUT(client, url, authorization: authorization, body: body, contentType: contentType, accept: accept) ;

      default: throw new StateError("Can't handle method: ${ EnumToString.parse(method) }") ;
    }
  }

  bool _withCredentials(HttpClient client, Authorization authorization) {
    if ( client.crossSiteWithCredentials != null ) return client.crossSiteWithCredentials ;

    if ( authorization != null && authorization.credential != null && authorization.credential.usesAuthorizationHeader ) return true ;
    return false ;
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
    ) ;
  }

  Future<HttpResponse> requestPOST(HttpClient client, String url, { Authorization authorization, Map<String,String> queryParameters, String body, String contentType, String accept }) {
    if (queryParameters != null && queryParameters.isNotEmpty && body == null) {
      var requestHeaders = buildRequestHeaders(client, url, authorization, body, contentType, accept);
      var formData = buildPOSTFormData(queryParameters, requestHeaders);

      return doHttpRequest(
          client,
          HttpRequest('POST', url, buildRequestURL(client, url, authorization),
              authorization: authorization,
              queryParameters: queryParameters,
              withCredentials: _withCredentials(client, authorization) ,
              requestHeaders: requestHeaders ,
              sendData: formData
          )
      );
    }
    else {
      return doHttpRequest(
          client,
          HttpRequest('POST' , url, buildRequestURL(client, url, authorization, queryParameters),
              authorization: authorization,
              queryParameters: queryParameters,
              withCredentials: _withCredentials(client, authorization) ,
              requestHeaders: buildRequestHeaders(client, url, authorization, body, contentType, accept),
              sendData: body
          )
      ) ;
    }
  }

  Future<HttpResponse> requestPUT(HttpClient client, String url, { Authorization authorization, String body, String contentType, String accept }) {
    return doHttpRequest(
        client,
        HttpRequest('PUT' , url, buildRequestURL(client, url, authorization),
            authorization: authorization,
            withCredentials: _withCredentials(client, authorization) ,
            requestHeaders: buildRequestHeaders(client, url, authorization, body, contentType, accept),
            sendData: body
        )
    ) ;
  }

  /////////////////////////////////////////////////////////////////////////////////////////

  Future<HttpResponse> doHttpRequest( HttpClient client, HttpRequest request ) ;

  String buildPOSTFormData(Map<String, String> data, [Map<String, String> requestHeaders]) {
    String formData = buildQueryString(data) ;

    if (requestHeaders != null) {
      requestHeaders.putIfAbsent('Content-Type', () => 'application/x-www-form-urlencoded; charset=UTF-8') ;
    }

    return formData ;
  }

  String buildQueryString(Map<String, String> data) {
    var parts = [];
    data.forEach((key, value) {
      var keyValue = "${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value)}" ;
      parts.add( keyValue);
    });

    String queryString = parts.join('&');
    return queryString ;
  }

  Map<String, String> buildRequestHeaders(HttpClient client, String url, [Authorization authorization, dynamic body, String contentType, String accept]) {
    var header = client.buildRequestHeaders(url) ;

    if (contentType != null) {
      if (header == null) header = {} ;
      header["Content-Type"] = contentType ;
    }

    if (accept != null) {
      if (header == null) header = {} ;
      header["Accept"] = accept ;
    }

    if ( authorization != null && authorization.credential != null && authorization.credential.usesAuthorizationHeader) {
      if (header == null) header = {} ;

      String buildHeaderLine = authorization.credential.buildHeaderLine();
      if (buildHeaderLine != null) {
        header["Authorization"] = buildHeaderLine;
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

}

class HttpClient {

  String baseURL ;

  HttpClientRequester _clientRequester ;

  HttpClientRequester get clientRequester => _clientRequester;

  HttpClient(String baseURL, [HttpClientRequester clientRequester]) {
    if (baseURL.endsWith("/")) baseURL = baseURL.substring(0,baseURL.length-1) ;
    this.baseURL = baseURL ;

    this._clientRequester = clientRequester ?? createHttpClientRequester() ;
  }
  
  bool isLocalhost() {
    return baseURL.startsWith(new RegExp('https?://localhost')) ;
  }

  Future<dynamic> requestJSON(HttpMethod method, String path, { Credential authorization, Map<String,String> queryParameters, String body, String contentType, String accept } ) async {
    return request(method, path, authorization: authorization, queryParameters: queryParameters, body: body, contentType: contentType, accept: accept).then((r) => _jsonDecode(r.body)) ;
  }

  Future<dynamic> getJSON(String path, { Credential authorization, Map<String,String> parameters } ) async {
    return get(path, authorization: authorization, parameters: parameters).then((r) => _jsonDecode(r.body)) ;
  }

  Future<dynamic> optionsJSON(String path, { Credential authorization, Map<String,String> parameters } ) async {
    return options(path, authorization: authorization, parameters: parameters).then((r) => _jsonDecode(r.body)) ;
  }

  Future<dynamic> postJSON(String path,  { Credential authorization, Map<String,String> parameters , String body , String contentType }) async {
    return post(path, authorization: authorization, parameters: parameters, body: body, contentType: contentType).then((r) => _jsonDecode(r.body)) ;
  }

  Future<dynamic> putJSON(String path,  { Credential authorization, String body , String contentType }) async {
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

  Authorization _requestAuthorizationResolved ;

  Authorization get resolvedAuthorization => _requestAuthorizationResolved ;

  Future<Authorization> _requestAuthorization(Credential credential) async {
    if ( credential != null ) {
      return Authorization( credential , this.authorizationProvider ) ;
    }
    else if (this.authorization == null && this.authorizationProvider == null) {
      return Future.value(null);
    }
    else {
      if ( _requestAuthorizationResolved != null ) {
        return _requestAuthorizationResolved ;
      }

      var requestAuthorizationResolvingFuture = _requestAuthorizationResolvingFuture ;
      if ( requestAuthorizationResolvingFuture != null ) {
        requestAuthorizationResolvingFuture.then( (c) {
          return _requestAuthorizationResolved ?? _requestAuthorizationResolving ;
        } ) ;
      }

      var authorization = Authorization( this.authorization , this.authorizationProvider ) ;

      var resolveCredential = authorization.resolveCredential(this, null);
      _requestAuthorizationResolving = authorization ;
      _requestAuthorizationResolvingFuture = resolveCredential ;

      return resolveCredential.then( (c) {
        _requestAuthorizationResolved = authorization ;
        _requestAuthorizationResolvingFuture = null ;
        _requestAuthorizationResolving = null ;
        return _requestAuthorizationResolved ;
      } ) ;
    }
  }

  Future<HttpResponse> request(HttpMethod method, String path, { Credential authorization, Map<String,String> queryParameters, String body, String contentType, String accept } ) async {
    var urlParameters = method == HttpMethod.GET || method == HttpMethod.OPTIONS ;
    String url = urlParameters ? _buildURL(path, queryParameters) :  _buildURL(path) ;
    var requestAuthorization = await _requestAuthorization(authorization);
    return _clientRequester.request(this, method, url, authorization: requestAuthorization, queryParameters: queryParameters, body: body, contentType: contentType, accept: accept);
  }

  Future<HttpResponse> get(String path, { Credential authorization, Map<String,String> parameters } ) async {
    String url = _buildURL(path, parameters);
    var requestAuthorization = await _requestAuthorization(authorization);
    return _clientRequester.requestGET( this, url, authorization: requestAuthorization );
  }

  Future<HttpResponse> options(String path, { Credential authorization, Map<String,String> parameters } ) async {
    String url = _buildURL(path, parameters);
    var requestAuthorization = await _requestAuthorization(authorization);
    return _clientRequester.requestOPTIONS(this, url, authorization: requestAuthorization);
  }

  Future<HttpResponse> post(String path, { Credential authorization, Map<String,String> parameters , String body , String contentType , String accept}) async {
    String url = _buildURL(path);

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

    var requestAuthorization = await _requestAuthorization(authorization);
    return _clientRequester.requestPOST(this, url, authorization: requestAuthorization, queryParameters: parameters, body: body, contentType: contentType, accept: accept);
  }

  Future<HttpResponse> put(String path, { Credential authorization, String body , String contentType , String accept}) async {
    String url = _buildURL(path);
    var requestAuthorization = await _requestAuthorization(authorization);
    return _clientRequester.requestPUT(this, url, authorization: requestAuthorization, body: body, contentType: contentType, accept: accept);
  }

  Uri _removeURIQueryParameters(var uri) {
    if ( uri.schema.toLowerCase() == "https" ) {
      return new Uri.https(uri.authority, uri.path) ;
    }
    else {
      return new Uri.http(uri.authority, uri.path) ;
    }
  }

  String _buildURL(String path, [Map<String,String> queryParameters]) {
    if ( !path.startsWith("/") ) path = "/$path" ;
    String url = "$baseURL$path" ;

    Uri uri = Uri.parse(url);

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

    if ( uri.scheme.toLowerCase() == "https" ) {
      uri2 = new Uri.https(uri.authority, uri.path, queryParameters) ;
    }
    else {
      uri2 = new Uri.http(uri.authority, uri.path, queryParameters) ;
    }

    String url2 = uri2.toString() ;

    print("Request URL: $url2") ;

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

typedef String SimulateResponse(String url, Map<String, String> queryParameters);

class HttpClientRequesterSimulation extends HttpClientRequester {

  /// GET

  Map<RegExp, SimulateResponse> _getPatterns = {} ;

  void replyGET(RegExp urlPattern, String response) {
    simulateGET(urlPattern , (u,p) => response) ;
  }

  void simulateGET(RegExp urlPattern, SimulateResponse response) {
    _getPatterns[urlPattern] = response ;
  }

  /// OPTIONS

  Map<RegExp, SimulateResponse> _optionsPatterns = {} ;

  void replyOPTIONS(RegExp urlPattern, String response) {
    simulateOPTIONS(urlPattern , (u,p) => response) ;
  }

  void simulateOPTIONS(RegExp urlPattern, SimulateResponse response) {
    _optionsPatterns[urlPattern] = response ;
  }

  /// POST

  Map<RegExp, SimulateResponse> _postPatterns = {} ;

  void replyPOST(RegExp urlPattern, String response) {
    simulatePOST(urlPattern , (u,p) => response) ;
  }

  void simulatePOST(RegExp urlPattern, SimulateResponse response) {
    _postPatterns[urlPattern] = response ;
  }

  /// PUT

  Map<RegExp, SimulateResponse> _putPatterns = {} ;

  void replyPUT(RegExp urlPattern, String response) {
    simulatePUT(urlPattern , (u,p) => response) ;
  }

  void simulatePUT(RegExp urlPattern, SimulateResponse response) {
    _putPatterns[urlPattern] = response ;
  }

  /// ANY

  Map<RegExp, SimulateResponse> _anyPatterns = {} ;

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
  Future<HttpResponse> doHttpRequest(HttpClient client, HttpRequest request) {
    var methodPatterns = methodSimulationPatterns(request.method) ;
    return _requestSimulated(client, request.method, request.requestURL, methodPatterns, request.queryParameters) ;
  }

  Future<HttpResponse> _requestSimulated(HttpClient client, String method, String url, Map<RegExp, SimulateResponse> methodPatterns, Map<String, String> queryParameters) {
    var resp = _findResponse(url, methodPatterns) ;

    if (resp == null) {
      resp = _findResponse(url, _anyPatterns) ;
    }

    if (resp == null) {
      return new Future.error("No simulated response[$method]") ;
    }

    var respVal = resp(url, queryParameters) ;

    HttpResponse restResponse = new HttpResponse(method, url, 200, respVal) ;

    return new Future.value(restResponse) ;
  }

}

