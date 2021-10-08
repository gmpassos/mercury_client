import 'dart:async';
import 'dart:math';

import 'package:swiss_knife/swiss_knife.dart';

import '../mercury_client.dart';

class _CacheRequest implements Comparable<_CacheRequest> {
  final HttpMethod _method;

  final String _url;

  final Map<String, String?>? _queryParameters;

  final dynamic _body;

  final String? _contentType;

  final String? _accept;

  final int instanceTime = DateTime.now().millisecondsSinceEpoch;

  late int _accessTime;

  _CacheRequest(this._method, this._url, this._queryParameters, this._body,
      this._contentType, this._accept) {
    _accessTime = instanceTime;
  }

  int get accessTime => _accessTime;

  bool isExpired(int timeout) {
    if (timeout <= 0) return false;

    var expireTime = accessTime + timeout;
    var now = DateTime.now().millisecondsSinceEpoch;
    return now > expireTime;
  }

  bool isValid(int timeout) {
    return !isExpired(timeout);
  }

  void updateAccessTime() {
    _accessTime = DateTime.now().millisecondsSinceEpoch;
  }

  _CacheRequest copy() {
    return _CacheRequest(
        _method,
        _url,
        _queryParameters != null ? Map.from(_queryParameters!) : null,
        _body,
        _contentType,
        _accept);
  }

  int memorySize() {
    var memory = 1 +
        4 +
        _url.length +
        (_body != null ? _body.length : 0) +
        (_contentType != null ? _contentType!.length : 0) +
        (_accept != null ? _accept!.length : 0);

    if (_queryParameters != null) {
      for (var entry in _queryParameters!.entries) {
        memory += entry.key.length;
        memory += entry.value?.length ?? 0;
      }
    }

    return memory as int;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CacheRequest &&
          runtimeType == other.runtimeType &&
          _method == other._method &&
          _url == other._url &&
          isEqualsDeep(_queryParameters, other._queryParameters) &&
          isEqualsDeep(_body, other._body) &&
          _contentType == other._contentType &&
          _accept == other._accept;

  @override
  int get hashCode =>
      _method.hashCode ^
      _url.hashCode ^
      deepHashCode(_queryParameters) ^
      deepHashCode(_body) ^
      (_contentType != null ? _contentType.hashCode : 0) ^
      (_accept != null ? _accept.hashCode : 0);

  @override
  int compareTo(_CacheRequest other) {
    return instanceTime < other.instanceTime
        ? -1
        : (instanceTime == other.instanceTime ? 0 : 1);
  }
}

typedef OnCachedResponse = void Function(HttpResponse cachedResponse);

/// A cache for [HttpClient]. Request originated from this cache are
/// stored in memory.
class HttpCache {
  /// Max memory that the cache can use.
  late int _maxCacheMemory;

  /// Timeout of stored requests.
  late Duration _timeout;

  /// If [true] shows cached requests in console.
  late bool verbose;

  HttpCache(
      {int maxCacheMemory = 0,
      Duration timeout = _noDuration,
      this.verbose = false}) {
    this.maxCacheMemory = maxCacheMemory;
    this.timeout = timeout;
  }

  void _log(String msg) {
    if (verbose) {
      print('[HttpCache] $msg');
    }
  }

  /// The maximum memory usage.
  int get maxCacheMemory => _maxCacheMemory;

  set maxCacheMemory(int value) {
    if (value <= 0) {
      _maxCacheMemory = 0;
    } else {
      if (value < 1024 * 4) value = 1024 * 4;
      _maxCacheMemory = value;
    }
  }

  /// Returns [true] if the cache has a memory limit.
  bool get hasMaxCacheMemory => _maxCacheMemory > 0;

  /// The timeout of stored requests.
  Duration get timeout => _timeout;

  static const Duration _noDuration = Duration(milliseconds: 0);

  set timeout(Duration value) {
    if (value.inMilliseconds <= 0) {
      _timeout = _noDuration;
    } else {
      if (value.inSeconds < 1) value = Duration(seconds: 1);
      _timeout = value;
    }
  }

  /// Returns [true] if the cached request have timeout.
  bool get hasTimeout => _timeout.inMilliseconds > 0;

  final Map<_CacheRequest, HttpResponse> _cache = {};

  MapEntry<_CacheRequest, HttpResponse>? _getCacheEntry(_CacheRequest key) {
    if (!_cache.containsKey(key)) return null;

    for (var entry in _cache.entries) {
      if (entry.key == key) return entry;
    }

    return null;
  }

  /// Returns the current cache usage of memory.
  int calculateCacheUsedMemory() {
    var total = 0;
    for (var entry in _cache.entries) {
      var memory = entry.key.memorySize() + entry.value.memorySize();
      total += memory;
    }
    return total;
  }

  /// Cleans the cached requests.
  int clearCache() {
    var usedMemory = calculateCacheUsedMemory();
    _cache.clear();
    return usedMemory;
  }

  int ensureCacheBelowMaxMemory([int extraMemoryNeeded = 0]) {
    if (!hasMaxCacheMemory) return 0;

    if (extraMemoryNeeded > 0) {
      var maxMem2 = maxCacheMemory - extraMemoryNeeded;
      if (maxMem2 < 10) {
        clearCache();
        return 0;
      } else {
        return cleanCache(maxMem2);
      }
    } else if (hasMaxCacheMemory) {
      return cleanCache(maxCacheMemory);
    }

    return 0;
  }

  int cleanCache(int maxMemory) {
    if (maxMemory <= 0) return -1;

    if (hasTimeout) {
      cleanCacheTimedOut();
    }

    var usedMemory = calculateCacheUsedMemory();
    if (usedMemory <= maxMemory) return 0;

    var entries =
        List<MapEntry<_CacheRequest, HttpResponse>>.from(_cache.entries);

    entries.sort((e1, e2) {
      var m1 = e1.key.memorySize() + e1.value.memorySize();
      var m2 = e2.key.memorySize() + e2.value.memorySize();
      return m1 < m2 ? 1 : (m1 == m2 ? 0 : -1);
    });

    var removeNeeded = usedMemory - maxMemory;

    var removed = 0;
    for (var entry in entries) {
      var memory = entry.key.memorySize() + entry.value.memorySize();
      _cache.remove(entry.key);
      removed += memory;

      _log('Removed cached entry> memory: $memory / $removeNeeded');

      if ((usedMemory - removed) <= maxMemory) break;
    }

    _log('Total removed memory: $removed / $usedMemory / $maxMemory');

    return removed;
  }

  int cleanCacheTimedOut([Duration? timeout]) {
    timeout ??= this.timeout;
    if (timeout.inMilliseconds <= 0) return 0;

    var entries =
        List<MapEntry<_CacheRequest, HttpResponse>>.from(_cache.entries);

    entries.sort((e1, e2) {
      var t1 = max(e1.key.accessTime, e1.value.accessTime!);
      var t2 = max(e2.key.accessTime, e2.value.accessTime!);
      return t1 < t2 ? -1 : (t1 == t2 ? 0 : 1);
    });

    var now = DateTime.now().millisecondsSinceEpoch;

    var removed = 0;
    for (var entry in entries) {
      var accessTime = max(entry.key.accessTime, entry.value.accessTime!);
      var elapsedTime = now - accessTime;
      if (elapsedTime <= timeout.inMilliseconds) break;

      var memory = entry.key.memorySize() + entry.value.memorySize();
      _cache.remove(entry.key);
      removed += memory;

      _log(
          'Removed cached entry> memory: $memory ; timeout: $elapsedTime / $timeout');
    }

    _log('Total removed memory: $removed');

    return removed;
  }

  /// Does a cached request using [httpClient].
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> request(
      HttpClient httpClient, HttpMethod method, String? path,
      {bool fullPath = false,
      Credential? authorization,
      Map<String, String?>? queryParameters,
      Object? body,
      String? contentType,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    var requestURL = httpClient.buildMethodRequestURL(
        method, path, fullPath, queryParameters);
    return this.requestURL(httpClient, method, requestURL,
        authorization: authorization,
        queryParameters: queryParameters,
        body: body,
        contentType: contentType,
        accept: accept,
        onStaleResponse: onStaleResponse,
        staleResponseDelay: staleResponseDelay);
  }

  /// Does a cached request using [httpClient] and [requestURL].
  ///
  /// - [authorization] a [Credential] for authorization.
  /// - [queryParameters] the request query parameters.
  /// - [body] the request body.
  /// - [contentType] the `Content-Type` header of the request [body].
  /// - [accept] the `Accept` header.
  /// - [onStaleResponse] function to call when a stale response (already cached)
  ///   is available to use while requesting a new response.
  /// - [staleResponseDelay] a delay to call [onStaleResponse] function. If the
  ///   new response arrives before this delay, no call to [onStaleResponse] will
  ///   be performed.
  Future<HttpResponse> requestURL(
      HttpClient? httpClient, HttpMethod method, String requestURL,
      {Credential? authorization,
      Map<String, String?>? queryParameters,
      Object? body,
      String? contentType,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    httpClient ??= HttpClient(requestURL);

    var cacheRequest = _CacheRequest(
        method, requestURL, queryParameters, body, contentType, accept);

    var cachedEntry = _getCacheEntry(cacheRequest);

    HttpResponse? cachedResponse;
    if (cachedEntry != null) {
      var cachedRequest = cachedEntry.key;
      cachedResponse = cachedEntry.value;

      if (cachedRequest.isValid(timeout.inMilliseconds)) {
        cachedRequest.updateAccessTime();

        _log('Cached request: $method > $requestURL > $cachedResponse');

        return cachedResponse;
      }
    }

    Completer<HttpResponse?>? cachedAvailableDelayed;
    if (onStaleResponse != null && cachedResponse != null) {
      if (staleResponseDelay != null && staleResponseDelay.inMilliseconds > 1) {
        cachedAvailableDelayed = Completer<HttpResponse?>();

        // ignore: unawaited_futures
        cachedAvailableDelayed.future.then((cachedResponse) {
          if (cachedResponse != null) {
            onStaleResponse(cachedResponse);
          }
        });

        Future.delayed(staleResponseDelay, () {
          if (!cachedAvailableDelayed!.isCompleted) {
            cachedAvailableDelayed.complete(cachedResponse);
          }
        });
      } else {
        onStaleResponse(cachedResponse);
      }
    }

    var ret = httpClient.requestURL(method, requestURL,
        authorization: authorization,
        queryParameters: queryParameters,
        body: body,
        contentType: contentType,
        accept: accept);

    var response = await ret;

    if (cachedAvailableDelayed != null && !cachedAvailableDelayed.isCompleted) {
      cachedAvailableDelayed.complete(null);
    }

    ensureCacheBelowMaxMemory(response.memorySize());

    _cache[cacheRequest] = response;

    var usedMemory = calculateCacheUsedMemory();

    _log('Used memory: $usedMemory / $maxCacheMemory');

    return response;
  }

  /// Gets a request already in cache using [httpClient].
  ///
  /// - See [getCachedRequestURL].
  HttpResponse? getCachedRequest(
      HttpClient httpClient, HttpMethod method, String path,
      {bool fullPath = false,
      Credential? authorization,
      Map<String, String?>? queryParameters,
      Object? body,
      String? contentType,
      String? accept}) {
    var requestURL = httpClient.buildMethodRequestURL(
        method, path, fullPath, queryParameters);
    return getCachedRequestURL(method, requestURL,
        authorization: authorization,
        queryParameters: queryParameters,
        body: body,
        contentType: contentType,
        accept: accept);
  }

  /// Gets a request already in cache using [httpClient] and [requestURL].
  HttpResponse? getCachedRequestURL(HttpMethod method, String requestURL,
      {Credential? authorization,
      Map<String, String?>? queryParameters,
      Object? body,
      String? contentType,
      String? accept}) {
    var cacheRequest = _CacheRequest(
        method, requestURL, queryParameters, body, contentType, accept);
    var cachedResponse = _cache[cacheRequest];

    if (cachedResponse != null) {
      _log('Cached request: $method > $requestURL > $cachedResponse');
      return cachedResponse;
    }

    return null;
  }

  /// Does a GET request using [url].
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> getURL(String url,
      {HttpClient? httpClient,
      bool fullPath = false,
      Credential? authorization,
      Map<String, String?>? parameters,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    return get(
      httpClient ?? HttpClient(url),
      httpClient != null ? url : null,
      fullPath: httpClient != null ? fullPath : false,
      parameters: parameters,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    );
  }

  /// Does a GET request.
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> get(HttpClient httpClient, String? path,
      {bool fullPath = false,
      Credential? authorization,
      Map<String, String?>? parameters,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    return request(httpClient, HttpMethod.GET, path,
        fullPath: fullPath,
        authorization: authorization,
        queryParameters: parameters,
        accept: accept,
        onStaleResponse: onStaleResponse,
        staleResponseDelay: staleResponseDelay);
  }

  /// Does a HEAD request.
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> head(HttpClient httpClient, String? path,
      {bool fullPath = false,
      Credential? authorization,
      Map<String, String?>? parameters,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    return request(httpClient, HttpMethod.HEAD, path,
        fullPath: fullPath,
        authorization: authorization,
        queryParameters: parameters,
        accept: accept,
        onStaleResponse: onStaleResponse,
        staleResponseDelay: staleResponseDelay);
  }

  /// Does an OPTIONS request.
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> options(HttpClient httpClient, String path,
      {bool fullPath = false,
      Credential? authorization,
      Map<String, String?>? parameters,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    return request(httpClient, HttpMethod.OPTIONS, path,
        fullPath: fullPath,
        authorization: authorization,
        queryParameters: parameters,
        accept: accept,
        onStaleResponse: onStaleResponse,
        staleResponseDelay: staleResponseDelay);
  }

  /// Does a POST request.
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> post(HttpClient httpClient, String path,
      {bool fullPath = false,
      Credential? authorization,
      Map<String, String?>? parameters,
      Object? body,
      String? contentType,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    return request(httpClient, HttpMethod.POST, path,
        fullPath: fullPath,
        authorization: authorization,
        queryParameters: parameters,
        body: body,
        contentType: contentType,
        accept: accept,
        onStaleResponse: onStaleResponse,
        staleResponseDelay: staleResponseDelay);
  }

  /// Does a PUT request.
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> put(HttpClient httpClient, String path,
      {bool fullPath = false,
      Credential? authorization,
      Object? body,
      String? contentType,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    return request(httpClient, HttpMethod.PUT, path,
        fullPath: fullPath,
        authorization: authorization,
        body: body,
        contentType: contentType,
        accept: accept,
        onStaleResponse: onStaleResponse,
        staleResponseDelay: staleResponseDelay);
  }

  /// Does a request and decodes response to JSON.
  ///
  /// - See [requestURL] documentation.
  Future<dynamic> requestJSON(
      HttpClient httpClient, HttpMethod method, String path,
      {bool fullPath = false,
      Credential? authorization,
      Map<String, String?>? queryParameters,
      Object? body,
      String? contentType,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    return request(httpClient, method, path,
            fullPath: fullPath,
            authorization: authorization,
            queryParameters: queryParameters,
            body: body,
            contentType: contentType,
            accept: accept,
            onStaleResponse: onStaleResponse,
            staleResponseDelay: staleResponseDelay)
        .then((r) => r.json);
  }

  /// Does a GET request and decodes response to JSON.
  ///
  /// - See [requestURL] documentation.
  Future<dynamic> getJSON(HttpClient httpClient, String path,
      {bool fullPath = false,
      Credential? authorization,
      Map<String, String?>? parameters,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    return get(httpClient, path,
            fullPath: fullPath,
            authorization: authorization,
            parameters: parameters,
            accept: accept,
            onStaleResponse: onStaleResponse,
            staleResponseDelay: staleResponseDelay)
        .then((r) => r.json);
  }

  /// Does an OPTIONS request and decodes response to JSON.
  ///
  /// - See [requestURL] documentation.
  Future<dynamic> optionsJSON(HttpClient httpClient, String path,
      {bool fullPath = false,
      Credential? authorization,
      Map<String, String?>? parameters,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    return options(httpClient, path,
            fullPath: fullPath,
            authorization: authorization,
            parameters: parameters,
            accept: accept,
            onStaleResponse: onStaleResponse,
            staleResponseDelay: staleResponseDelay)
        .then((r) => r.json);
  }

  /// Does a POST request and decodes response to JSON.
  ///
  /// - See [requestURL] documentation.
  Future<dynamic> postJSON(HttpClient httpClient, String path,
      {bool fullPath = false,
      Credential? authorization,
      Map<String, String?>? parameters,
      Object? body,
      String? contentType,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    return post(httpClient, path,
            fullPath: fullPath,
            authorization: authorization,
            parameters: parameters,
            body: body,
            contentType: contentType,
            accept: accept,
            onStaleResponse: onStaleResponse,
            staleResponseDelay: staleResponseDelay)
        .then((r) => r.json);
  }

  /// Does a PUT request and decodes response to JSON.
  ///
  /// - See [requestURL] documentation.
  Future<dynamic> putJSON(HttpClient httpClient, String path,
      {bool fullPath = false,
      Credential? authorization,
      Object? body,
      String? contentType,
      String? accept,
      OnCachedResponse? onStaleResponse,
      Duration? staleResponseDelay}) async {
    return put(httpClient, path,
            fullPath: fullPath,
            authorization: authorization,
            body: body,
            contentType: contentType,
            accept: accept,
            onStaleResponse: onStaleResponse,
            staleResponseDelay: staleResponseDelay)
        .then((r) => r.json);
  }

  @override
  String toString() {
    return 'HttpCache{cache: ${_cache.length}: maxCacheMemory: $_maxCacheMemory, timeout: $_timeout, verbose: $verbose}';
  }
}
