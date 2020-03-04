import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../mercury_client.dart';


class _CacheRequest implements Comparable<_CacheRequest> {

  final HttpMethod _method ;
  final String _url ;
  final Map<String,String> _queryParameters ;
  final String _body ;
  final String _contentType ;
  final String _accept ;

  final int instanceTime = DateTime.now().millisecondsSinceEpoch ;
  int _accessTime ;

  _CacheRequest(this._method, this._url, this._queryParameters, this._body, this._contentType, this._accept) {
    _accessTime = instanceTime ;
  }

  int get accessTime => _accessTime;

  void updateAccessTime() {
    _accessTime = DateTime.now().millisecondsSinceEpoch ;
  }

  _CacheRequest copy() {
    return _CacheRequest(_method, _url, _queryParameters != null ? Map.from(_queryParameters) : null, _body, _contentType, _accept) ;
  }

  int memorySize() {
    var memory = 1 + 4 + (_url != null ? _url.length : 0) + (_body != null ? _body.length : 0) + (_contentType != null ? _contentType.length : 0) + (_accept != null ? _accept.length : 0) ;

    if (_queryParameters != null) {
      for (var entry in _queryParameters.entries) {
        memory += ( entry.key != null ? entry.key.length : 0 ) ;
        memory += ( entry.value != null ? entry.value.length : 0 ) ;
      }
    }

    return memory ;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CacheRequest &&
          runtimeType == other.runtimeType &&
          _method == other._method &&
          _url == other._url &&
          _queryParameters == other._queryParameters &&
          _body == other._body &&
          _contentType == other._contentType &&
          _accept == other._accept;

  @override
  int get hashCode =>
      _method.hashCode ^
      (_url != null ? _url.hashCode : 0) ^
      (_queryParameters != null ? _queryParameters.hashCode : 0) ^
      (_body != null ? _body.hashCode : 0) ^
      (_contentType != null ? _contentType.hashCode : 0) ^
      (_accept != null ? _accept.hashCode : 0) ;


  @override
  int compareTo(_CacheRequest other) {
    return instanceTime < other.instanceTime ? -1 : ( instanceTime == other.instanceTime ? 0 : 1 ) ;
  }


}

class HttpCache {

  int _maxCacheMemory ;
  int _timeout ;

  HttpCache( [int maxCacheMemory , int timeout] ) {
    this.maxCacheMemory = maxCacheMemory ;
    this.timeout = timeout ;
  }

  bool verbose = true ;

  bool get isVerbose => verbose != null && verbose ;

  int get maxCacheMemory => _maxCacheMemory;

  bool get hasMaxCacheMemory => _maxCacheMemory != null && _maxCacheMemory > 0 ;

  set maxCacheMemory(int value) {
    if (value == null || value <= 0) {
      _maxCacheMemory = null;
    }
    else {
      if (value < 1024*4) value = 1024*4 ;
      _maxCacheMemory = value ;
    }
  }

  int get timeout => _timeout;

  bool get hasTimeout => _timeout != null && _timeout > 0 ;

  set timeout(int value) {
    if (value == null || value <= 0) {
      _timeout = null;
    }
    else {
      if (value < 1000) value = 1000 ;
      _timeout = value ;
    }
  }


  final Map<_CacheRequest,HttpResponse> _cache = {} ;

  int calculateCacheUsedMemory() {
    var total = 0 ;
    for (var entry in _cache.entries) {
      var memory = entry.key.memorySize() + entry.value.memorySize() ;
      total += memory ;
    }
    return total ;
  }

  int clearCache() {
    var usedMemory = calculateCacheUsedMemory() ;
    _cache.clear();
    return usedMemory ;
  }

  int ensureCacheBelowMaxMemory( [int extraMemoryNeeded] ) {
    if (!hasMaxCacheMemory) return 0 ;

    if (extraMemoryNeeded != null && extraMemoryNeeded > 0) {
      var maxMem2 = maxCacheMemory-extraMemoryNeeded;
      if (maxMem2 < 10) {
        clearCache() ;
        return 0 ;
      }
      else {
        return cleanCache(maxMem2);
      }
    }
    else if (hasMaxCacheMemory) {
      return cleanCache(maxCacheMemory);
    }

    return 0 ;
  }

  int cleanCache(int maxMemory) {
    if (maxMemory == null || maxMemory <= 0) return -1 ;

    if (hasTimeout) {
      cleanCacheTimedOut();
    }

    var usedMemory = calculateCacheUsedMemory() ;
    if (usedMemory <= maxMemory) return 0 ;

    // ignore: omit_local_variable_types
    List<MapEntry<_CacheRequest,HttpResponse>> entries = List.from( _cache.entries ) ;

    entries.sort( (e1,e2) {
      var m1 = e1.key.memorySize() + e1.value.memorySize() ;
      var m2 = e2.key.memorySize() + e2.value.memorySize() ;
      return m1 < m2 ? 1 : (m1 == m2 ? 0 : -1) ;
    } ) ;

    var removeNeeded = usedMemory - maxMemory ;

    var removed = 0 ;
    for (var entry in entries) {
      var memory = entry.key.memorySize() + entry.value.memorySize() ;
      _cache.remove(entry.key) ;
      removed += memory ;

      if (isVerbose) print('[HttpCache] Removed cached entry> memory: $memory / $removeNeeded');

      if ( (usedMemory-removed) <= maxMemory ) break ;
    }

    if (isVerbose) print('[HttpCache] Total removed memory: $removed / $usedMemory / $maxMemory');

    return removed ;
  }

  int cleanCacheTimedOut( [int timeout] ) {
    timeout ??= this.timeout;
    if (timeout == null || timeout <= 0) return 0 ;

    // ignore: omit_local_variable_types
    List<MapEntry<_CacheRequest,HttpResponse>> entries = List.from( _cache.entries ) ;

    entries.sort( (e1,e2) {
      var t1 = max( e1.key.accessTime , e1.value.accessTime ) ;
      var t2 = max( e2.key.accessTime , e2.value.accessTime ) ;
      return t1 < t2 ? -1 : (t1 == t2 ? 0 : 1) ;
    } ) ;

    var now = DateTime.now().millisecondsSinceEpoch ;

    var removed = 0 ;
    for (var entry in entries) {
      var accessTime = max( entry.key.accessTime , entry.value.accessTime ) ;
      var elapsedTime = now-accessTime;
      if ( elapsedTime <= timeout ) break;

      var memory = entry.key.memorySize() + entry.value.memorySize() ;
      _cache.remove(entry.key) ;
      removed += memory ;

      if (isVerbose) print('[HttpCache] Removed cached entry> memory: $memory ; timeout: $elapsedTime / $timeout');
    }

    if (isVerbose) print('[HttpCache] Total removed memory: $removed');

    return removed ;
  }

  Future<HttpResponse> request(HttpClient httpClient, HttpMethod method, String path, { bool fullPath, Credential authorization, Map<String,String> queryParameters, String body, String contentType, String accept } ) async {
    var requestURL = httpClient.buildMethodRequestURL(method, path, fullPath, queryParameters) ;
    return this.requestURL(httpClient, method, requestURL, authorization: authorization, queryParameters: queryParameters, body: body, contentType: contentType, accept: accept) ;
  }

  Future<HttpResponse> requestURL(HttpClient httpClient, HttpMethod method, String requestURL, { Credential authorization, Map<String,String> queryParameters, String body, String contentType, String accept } ) async {
    httpClient ??= HttpClient(requestURL);

    var cacheRequest = _CacheRequest(method, requestURL, queryParameters, body, contentType, accept) ;

    var cachedResponse = _cache[cacheRequest] ;

    if (cachedResponse != null) {

      if (isVerbose) print('[HttpCache] Cached request: $method > $requestURL > $cachedResponse');
      return cachedResponse ;
    }

    var response = await httpClient.requestURL(method, requestURL, authorization: authorization, queryParameters: queryParameters, body: body, contentType: contentType, accept: accept);
    if (response == null) return null ;

    ensureCacheBelowMaxMemory( response.memorySize() ) ;

    _cache[cacheRequest] = response ;

    var usedMemory = calculateCacheUsedMemory() ;

    if (isVerbose) print('[HttpCache] Used memory: $usedMemory / $maxCacheMemory');

    return response;
  }

  HttpResponse getCachedRequest(HttpClient httpClient, HttpMethod method, String path, { bool fullPath, Credential authorization, Map<String,String> queryParameters, String body, String contentType, String accept } ) {
    var requestURL = httpClient.buildMethodRequestURL(method, path, fullPath, queryParameters) ;
    return getCachedRequestURL(method, requestURL, authorization: authorization, queryParameters: queryParameters, body: body, contentType: contentType, accept: accept) ;
  }

  HttpResponse getCachedRequestURL(HttpMethod method, String requestURL, { Credential authorization, Map<String,String> queryParameters, String body, String contentType, String accept } ) {
    var cacheRequest = _CacheRequest(method, requestURL, queryParameters, body, contentType, accept) ;
    var cachedResponse = _cache[cacheRequest] ;

    if (cachedResponse != null) {
      if (isVerbose) print('[HttpCache] Cached request: $method > $requestURL > $cachedResponse');
      return cachedResponse ;
    }

    return null ;
  }

  Future<HttpResponse> getURL( String url, { bool fullPath, Credential authorization, Map<String,String> parameters } ) async {
    return get( HttpClient(url) , null, fullPath: fullPath, parameters: parameters ) ;
  }

  Future<HttpResponse> get(HttpClient httpClient, String path, { bool fullPath, Credential authorization, Map<String,String> parameters } ) async {
    return request(httpClient, HttpMethod.GET, path, fullPath: fullPath, authorization:  authorization, queryParameters: parameters) ;
  }

  Future<HttpResponse> options(HttpClient httpClient, String path, { bool fullPath, Credential authorization, Map<String,String> parameters } ) async {
    return request(httpClient, HttpMethod.OPTIONS, path, fullPath: fullPath, authorization:  authorization, queryParameters: parameters) ;
  }

  Future<HttpResponse> post(HttpClient httpClient, String path, { bool fullPath, Credential authorization, Map<String,String> parameters , String body , String contentType , String accept}) async {
    return request(httpClient, HttpMethod.POST, path, fullPath: fullPath, authorization:  authorization, queryParameters: parameters, body: body, contentType: contentType, accept: accept) ;
  }


  Future<HttpResponse> put(HttpClient httpClient, String path, { bool fullPath, Credential authorization, String body , String contentType , String accept}) async {
    return request(httpClient, HttpMethod.PUT, path, fullPath: fullPath, authorization: authorization, body: body, contentType: contentType, accept: accept);
  }

  ////

  Future<dynamic> requestJSON(HttpClient httpClient, HttpMethod method, String path, { bool fullPath, Credential authorization, Map<String,String> queryParameters, String body, String contentType, String accept } ) async {
    return request(httpClient, method, path, fullPath: fullPath, authorization: authorization, queryParameters: queryParameters, body: body, contentType: contentType, accept: accept).then((r) => _jsonDecode(r.body)) ;
  }

  Future<dynamic> getJSON(HttpClient httpClient, String path, { bool fullPath, Credential authorization, Map<String,String> parameters } ) async {
    return get(httpClient, path, fullPath: fullPath, authorization: authorization, parameters: parameters).then((r) => _jsonDecode(r.body)) ;
  }

  Future<dynamic> optionsJSON(HttpClient httpClient, String path, { bool fullPath, Credential authorization, Map<String,String> parameters } ) async {
    return options(httpClient, path, fullPath: fullPath, authorization: authorization, parameters: parameters).then((r) => _jsonDecode(r.body)) ;
  }

  Future<dynamic> postJSON(HttpClient httpClient, String path,  { bool fullPath, Credential authorization, Map<String,String> parameters , String body , String contentType }) async {
    return post(httpClient, path, fullPath: fullPath, authorization: authorization, parameters: parameters, body: body, contentType: contentType).then((r) => _jsonDecode(r.body)) ;
  }

  Future<dynamic> putJSON(HttpClient httpClient, String path,  { bool fullPath, Credential authorization, String body , String contentType }) async {
    return put(httpClient, path, fullPath: fullPath, authorization: authorization, body: body, contentType: contentType).then((r) => _jsonDecode(r.body)) ;
  }

  dynamic _jsonDecode(String s) {
    return jsonDecode(s) ;
  }

}
