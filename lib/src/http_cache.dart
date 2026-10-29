import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:swiss_knife/swiss_knife.dart';

import '../mercury_client.dart';

class _CacheRequest implements Comparable<_CacheRequest> {
  final HttpMethod _method;

  final String _url;

  final Map<String, String?>? _queryParameters;

  final dynamic _body;

  final String? _contentType;

  final String? _accept;

  /// Identifies the [Credential] of the request: a response for one
  /// credential is not for another.
  final String? _authorization;

  final int instanceTime = DateTime.now().millisecondsSinceEpoch;

  late int _accessTime;

  _CacheRequest(
    this._method,
    this._url,
    Map<String, String?>? queryParameters,
    Object? body,
    this._contentType,
    this._accept, [
    Credential? authorization,
  ]) : // Copies: a key changed by the caller would be lost in the cache.
       _queryParameters = queryParameters != null
           ? Map<String, String?>.of(queryParameters)
           : null,
       _body = body is Map || (body is List && body is! TypedData)
           ? deepCopy(body)
           : body,
       _authorization = _credentialKey(authorization) {
    _accessTime = instanceTime;
  }

  /// The data the [credential] adds to a request: its `Authorization`
  /// header, URL parameters or JSON body field (or its identity).
  static String? _credentialKey(Credential? credential) {
    if (credential == null) return null;

    String? key = credential.buildAuthorizationHeaderLine();
    if (key == null) {
      if (credential is JSONBodyCredential) {
        key = encodeJSON({credential.field: credential.authorization});
      } else {
        var url = credential.buildURL('http://h/');
        key = url != null && url != 'http://h/'
            ? url
            : identityHashCode(credential).toString();
      }
    }

    return '${credential.type}:$key';
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

  int memorySize() {
    var memory =
        1 +
        4 +
        _url.length +
        _bodyMemorySize(_body) +
        (_contentType?.length ?? 0) +
        (_accept?.length ?? 0) +
        (_authorization?.length ?? 0);

    final queryParameters = _queryParameters;
    if (queryParameters != null) {
      for (var entry in queryParameters.entries) {
        memory += entry.key.length;
        memory += entry.value?.length ?? 0;
      }
    }

    return memory;
  }

  /// The [body] can be of any type (only some have a `length`).
  static int _bodyMemorySize(Object? body) {
    if (body == null) return 0;
    if (body is String) return body.length;
    if (body is TypedData) return body.lengthInBytes;
    if (body is ByteBuffer) return body.lengthInBytes;
    if (body is List) return body.length * 8;
    if (body is Map) return body.length * 16;
    return 8;
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
          _accept == other._accept &&
          _authorization == other._authorization;

  @override
  late final int hashCode =
      _method.hashCode ^
      _url.hashCode ^
      deepHashCode(_queryParameters) ^
      deepHashCode(_body) ^
      _contentType.hashCode ^
      _accept.hashCode ^
      _authorization.hashCode;

  @override
  int compareTo(_CacheRequest other) {
    return instanceTime < other.instanceTime
        ? -1
        : (instanceTime == other.instanceTime ? 0 : 1);
  }
}

/// A cached [response] of a [request], with its [memory] usage.
class _CacheEntry {
  final _CacheRequest request;

  final HttpResponse response;

  /// Computed once: [request] and [response] don't change.
  final int memory;

  static int _idCount = 0;

  /// Orders entries of the same [memory] (in [HttpCache._bySize]).
  final int _id = ++_idCount;

  _CacheEntry(this.request, this.response)
    : memory = request.memorySize() + response.memorySize();

  /// The largest first.
  static int compareBySize(_CacheEntry a, _CacheEntry b) {
    var c = b.memory.compareTo(a.memory);
    return c != 0 ? c : a._id.compareTo(b._id);
  }

  int get accessTime => max(request.accessTime, response.accessTime ?? 0);
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

  HttpCache({
    int maxCacheMemory = 0,
    Duration timeout = _noDuration,
    this.verbose = false,
  }) {
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

  /// The entries by request: the stored request (with its access time) is
  /// the one of the entry, not the (equal) key used to find it.
  final Map<_CacheRequest, _CacheEntry> _cache = {};

  /// The entries, the largest first: the ones removed first by [cleanCache]
  /// (without sorting all the entries for each one stored).
  final SplayTreeSet<_CacheEntry> _bySize = SplayTreeSet(
    _CacheEntry.compareBySize,
  );

  /// The sum of the [_CacheEntry.memory] of all entries.
  int _usedMemory = 0;

  /// When [cleanCache] last called [cleanCacheTimedOut].
  int _lastCleanTimedOut = 0;

  void _putEntry(_CacheEntry entry) {
    _removeEntry(entry.request);
    _cache[entry.request] = entry;
    _bySize.add(entry);
    _usedMemory += entry.memory;
  }

  _CacheEntry? _removeEntry(_CacheRequest request) {
    var entry = _cache.remove(request);
    if (entry != null) {
      _bySize.remove(entry);
      _usedMemory -= entry.memory;
    }
    return entry;
  }

  /// Returns the current cache usage of memory.
  int calculateCacheUsedMemory() => _usedMemory;

  /// Cleans the cached requests.
  int clearCache() {
    var usedMemory = _usedMemory;
    _cache.clear();
    _bySize.clear();
    _usedMemory = 0;
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

    if (_usedMemory <= maxMemory) return 0;

    // Over the limit: the timed out entries first. At most once per second
    // (all the entries are checked), the minimal [timeout].
    if (hasTimeout) {
      var now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastCleanTimedOut >= 1000) {
        _lastCleanTimedOut = now;
        cleanCacheTimedOut();
      }
    }

    var usedMemory = _usedMemory;
    if (usedMemory <= maxMemory) return 0;

    var removeNeeded = usedMemory - maxMemory;

    var removed = 0;
    while (_bySize.isNotEmpty) {
      // The largest first.
      var entry = _bySize.first;
      var memory = entry.memory;
      _removeEntry(entry.request);
      removed += memory;

      if (verbose) {
        _log('Removed cached entry> memory: $memory / $removeNeeded');
      }

      if ((usedMemory - removed) <= maxMemory) break;
    }

    if (verbose) {
      _log('Total removed memory: $removed / $usedMemory / $maxMemory');
    }

    return removed;
  }

  int cleanCacheTimedOut([Duration? timeout]) {
    timeout ??= this.timeout;
    if (timeout.inMilliseconds <= 0) return 0;

    var now = DateTime.now().millisecondsSinceEpoch;
    var timeoutMs = timeout.inMilliseconds;

    var removed = 0;
    for (var entry in _cache.values.toList()) {
      var elapsedTime = now - entry.accessTime;
      if (elapsedTime <= timeoutMs) continue;

      var memory = entry.memory;
      _removeEntry(entry.request);
      removed += memory;

      if (verbose) {
        _log(
          'Removed cached entry> memory: $memory ; timeout: $elapsedTime / $timeout',
        );
      }
    }

    if (verbose) _log('Total removed memory: $removed');

    return removed;
  }

  /// Does a cached request using [httpClient].
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> request(
    HttpClient httpClient,
    HttpMethod method,
    String? path, {
    bool fullPath = false,
    Credential? authorization,
    Map<String, String?>? queryParameters,
    Object? body,
    String? contentType,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    var requestURL = httpClient.buildMethodRequestURL(
      method,
      path,
      fullPath,
      queryParameters,
    );
    return this.requestURL(
      httpClient,
      method,
      requestURL,
      authorization: authorization,
      queryParameters: queryParameters,
      body: body,
      contentType: contentType,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    );
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
    HttpClient? httpClient,
    HttpMethod method,
    String requestURL, {
    Credential? authorization,
    Map<String, String?>? queryParameters,
    Object? body,
    String? contentType,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    httpClient ??= HttpClient(requestURL);

    var cacheRequest = _CacheRequest(
      method,
      requestURL,
      queryParameters,
      body,
      contentType,
      accept,
      authorization,
    );

    var cachedEntry = _cache[cacheRequest];

    HttpResponse? cachedResponse;
    if (cachedEntry != null) {
      var cachedRequest = cachedEntry.request;
      cachedResponse = cachedEntry.response;

      if (cachedRequest.isValid(timeout.inMilliseconds)) {
        cachedRequest.updateAccessTime();

        if (verbose) {
          _log('Cached request: $method > $requestURL > $cachedResponse');
        }

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

    var ret = httpClient.requestURL(
      method,
      requestURL,
      authorization: authorization,
      queryParameters: queryParameters,
      body: body,
      contentType: contentType,
      accept: accept,
    );

    var response = await ret;

    if (cachedAvailableDelayed != null && !cachedAvailableDelayed.isCompleted) {
      cachedAvailableDelayed.complete(null);
    }

    // A network or server error is not cached (a stale response, if any, is
    // kept): the next request tries again.
    if (response.isStatusNetworkError || response.isStatusServerError) {
      return response;
    }

    var entry = _CacheEntry(cacheRequest, response);

    // Without the expired entry of this request: not counted as used memory.
    _removeEntry(cacheRequest);
    ensureCacheBelowMaxMemory(entry.memory);

    _putEntry(entry);

    if (verbose) _log('Used memory: $_usedMemory / $maxCacheMemory');

    return response;
  }

  /// Gets a request already in cache using [httpClient].
  ///
  /// - See [getCachedRequestURL].
  HttpResponse? getCachedRequest(
    HttpClient httpClient,
    HttpMethod method,
    String path, {
    bool fullPath = false,
    Credential? authorization,
    Map<String, String?>? queryParameters,
    Object? body,
    String? contentType,
    String? accept,
  }) {
    var requestURL = httpClient.buildMethodRequestURL(
      method,
      path,
      fullPath,
      queryParameters,
    );
    return getCachedRequestURL(
      method,
      requestURL,
      authorization: authorization,
      queryParameters: queryParameters,
      body: body,
      contentType: contentType,
      accept: accept,
    );
  }

  /// Gets a request already in cache using [httpClient] and [requestURL].
  HttpResponse? getCachedRequestURL(
    HttpMethod method,
    String requestURL, {
    Credential? authorization,
    Map<String, String?>? queryParameters,
    Object? body,
    String? contentType,
    String? accept,
  }) {
    var cacheRequest = _CacheRequest(
      method,
      requestURL,
      queryParameters,
      body,
      contentType,
      accept,
      authorization,
    );
    var cachedEntry = _cache[cacheRequest];

    // An expired entry: not returned (as by [requestURL]).
    var cachedResponse =
        cachedEntry != null &&
            cachedEntry.request.isValid(timeout.inMilliseconds)
        ? cachedEntry.response
        : null;

    if (cachedResponse != null) {
      if (verbose) {
        _log('Cached request: $method > $requestURL > $cachedResponse');
      }
      return cachedResponse;
    }

    return null;
  }

  /// Does a GET request using [url].
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> getURL(
    String url, {
    HttpClient? httpClient,
    bool fullPath = false,
    Credential? authorization,
    Map<String, String?>? parameters,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    return get(
      httpClient ?? HttpClient(url),
      httpClient != null ? url : null,
      fullPath: httpClient != null ? fullPath : false,
      authorization: authorization,
      parameters: parameters,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    );
  }

  /// Does a GET request.
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> get(
    HttpClient httpClient,
    String? path, {
    bool fullPath = false,
    Credential? authorization,
    Map<String, String?>? parameters,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    return request(
      httpClient,
      HttpMethod.GET,
      path,
      fullPath: fullPath,
      authorization: authorization,
      queryParameters: parameters,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    );
  }

  /// Does a HEAD request.
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> head(
    HttpClient httpClient,
    String? path, {
    bool fullPath = false,
    Credential? authorization,
    Map<String, String?>? parameters,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    return request(
      httpClient,
      HttpMethod.HEAD,
      path,
      fullPath: fullPath,
      authorization: authorization,
      queryParameters: parameters,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    );
  }

  /// Does an OPTIONS request.
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> options(
    HttpClient httpClient,
    String path, {
    bool fullPath = false,
    Credential? authorization,
    Map<String, String?>? parameters,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    return request(
      httpClient,
      HttpMethod.OPTIONS,
      path,
      fullPath: fullPath,
      authorization: authorization,
      queryParameters: parameters,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    );
  }

  /// Does a POST request.
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> post(
    HttpClient httpClient,
    String path, {
    bool fullPath = false,
    Credential? authorization,
    Map<String, String?>? parameters,
    Object? body,
    String? contentType,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    return request(
      httpClient,
      HttpMethod.POST,
      path,
      fullPath: fullPath,
      authorization: authorization,
      queryParameters: parameters,
      body: body,
      contentType: contentType,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    );
  }

  /// Does a PUT request.
  ///
  /// - See [requestURL] documentation.
  Future<HttpResponse> put(
    HttpClient httpClient,
    String path, {
    bool fullPath = false,
    Credential? authorization,
    Object? body,
    String? contentType,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    return request(
      httpClient,
      HttpMethod.PUT,
      path,
      fullPath: fullPath,
      authorization: authorization,
      body: body,
      contentType: contentType,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    );
  }

  /// Does a request and decodes response to JSON.
  ///
  /// - See [requestURL] documentation.
  Future<dynamic> requestJSON(
    HttpClient httpClient,
    HttpMethod method,
    String path, {
    bool fullPath = false,
    Credential? authorization,
    Map<String, String?>? queryParameters,
    Object? body,
    String? contentType,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    return request(
      httpClient,
      method,
      path,
      fullPath: fullPath,
      authorization: authorization,
      queryParameters: queryParameters,
      body: body,
      contentType: contentType,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    ).then((r) => r.json);
  }

  /// Does a GET request and decodes response to JSON.
  ///
  /// - See [requestURL] documentation.
  Future<dynamic> getJSON(
    HttpClient httpClient,
    String path, {
    bool fullPath = false,
    Credential? authorization,
    Map<String, String?>? parameters,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    return get(
      httpClient,
      path,
      fullPath: fullPath,
      authorization: authorization,
      parameters: parameters,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    ).then((r) => r.json);
  }

  /// Does an OPTIONS request and decodes response to JSON.
  ///
  /// - See [requestURL] documentation.
  Future<dynamic> optionsJSON(
    HttpClient httpClient,
    String path, {
    bool fullPath = false,
    Credential? authorization,
    Map<String, String?>? parameters,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    return options(
      httpClient,
      path,
      fullPath: fullPath,
      authorization: authorization,
      parameters: parameters,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    ).then((r) => r.json);
  }

  /// Does a POST request and decodes response to JSON.
  ///
  /// - See [requestURL] documentation.
  Future<dynamic> postJSON(
    HttpClient httpClient,
    String path, {
    bool fullPath = false,
    Credential? authorization,
    Map<String, String?>? parameters,
    Object? body,
    String? contentType,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    return post(
      httpClient,
      path,
      fullPath: fullPath,
      authorization: authorization,
      parameters: parameters,
      body: body,
      contentType: contentType,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    ).then((r) => r.json);
  }

  /// Does a PUT request and decodes response to JSON.
  ///
  /// - See [requestURL] documentation.
  Future<dynamic> putJSON(
    HttpClient httpClient,
    String path, {
    bool fullPath = false,
    Credential? authorization,
    Object? body,
    String? contentType,
    String? accept,
    OnCachedResponse? onStaleResponse,
    Duration? staleResponseDelay,
  }) async {
    return put(
      httpClient,
      path,
      fullPath: fullPath,
      authorization: authorization,
      body: body,
      contentType: contentType,
      accept: accept,
      onStaleResponse: onStaleResponse,
      staleResponseDelay: staleResponseDelay,
    ).then((r) => r.json);
  }

  @override
  String toString() {
    return 'HttpCache{cache: ${_cache.length}: maxCacheMemory: $_maxCacheMemory, timeout: $_timeout, verbose: $verbose}';
  }
}
