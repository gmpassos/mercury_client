import 'package:swiss_knife/swiss_knife.dart';

import 'http_cache.dart';
import 'http_client.dart';

/// A Class able to do a HTTP request based in properties:
/// - httpMethod: The HTTP Method name.
/// - scheme: URL scheme.
/// - host: URL Host.
/// - path: URL path.
/// - bodyType: The request body type.
/// - body: The request body.
/// - responseType: desired response type: JSON, JSONPaging
class HttpRequester {
  final MapProperties config;

  final MapProperties properties;

  HttpCache? httpCache;

  late String _scheme;

  late String _host;

  late HttpMethod _httpMethod;

  late String _path;

  Map<String, String?>? _parameters;

  String? _bodyType;

  String? _body;

  String? _responseType;

  static MapProperties _asMapProperties(Object? o, [MapProperties? def]) {
    if (o == null) return def ?? MapProperties();

    if (o is MapProperties) return o;
    if (o is Map<String, String>) return MapProperties.fromStringProperties(o);
    if (o is Map<String, Object?>) return MapProperties.fromProperties(o);
    if (o is Map) return MapProperties.fromMap(o);

    return def ?? MapProperties();
  }

  HttpRequester(Map<String, Object?> config,
      [Map<String, Object?>? properties, this.httpCache])
      : config = _asMapProperties(config),
        properties = _asMapProperties(properties) {
    var config = this.config;

    var schemeType = config
        .findPropertyAsStringTrimLC(['scheme', 'protocol', 'type'], 'http')!;
    var secure = config.findPropertyAsBool(['secure', 'ssl', 'https'], false)!;

    var host = config.getPropertyAsStringTrimLC('host');
    var method = config
        .findPropertyAsStringTrimLC(['method', 'http_method', 'httpMethod']);

    var path = config.getPropertyAsString('path', '/');

    var parameters = config.getPropertyAsStringMap('parameters');

    var bodyType = config.findPropertyAsStringTrimLC([
      'body_type',
      'bodyType',
      'content_type',
      'content-type',
      'contentType'
    ]);

    var body = config.getPropertyAsStringTrimLC('body');

    var responseType =
        config.findPropertyAsStringTrimLC(['response_type', 'responseType']);

    if (responseType != null) responseType = responseType.toLowerCase();

    var runtimeUri = getHttpClientRuntimeUri();

    var scheme = schemeType == 'https'
        ? 'https'
        : (schemeType == 'http' ? 'http' : runtimeUri.scheme);

    if (secure) {
      scheme = 'https';
    }

    if (host == null) {
      host = '${runtimeUri.host}:${runtimeUri.port}';
    } else if (RegExp(r'^:?\d+$').hasMatch(host)) {
      var port = host;
      if (port.startsWith(':')) port = port.substring(1);
      host = '${runtimeUri.host}:$port';
    }

    var httpMethod = getHttpMethod(method, HttpMethod.GET)!;

    var pathBuilt = '/';

    if (path != null) {
      pathBuilt = path.contains('{{')
          ? buildStringPattern(path, this.properties.toStringProperties()) ??
              path
          : path;
    }

    String? bodyBuilt;

    if (body != null) {
      bodyBuilt = body.contains('{{')
          ? buildStringPattern(body, this.properties.toStringProperties())
          : body;
    }

    _host = host;
    _scheme = scheme;
    _httpMethod = httpMethod;
    _path = pathBuilt;
    _parameters = parameters;
    _responseType = responseType;
    _bodyType = bodyType;
    _body = bodyBuilt;
  }

  String get scheme => _scheme;

  String get host => _host;

  HttpMethod get httpMethod => _httpMethod;

  String get path => _path;

  Map<String, String?>? get parameters => _parameters;

  String? get bodyType => _bodyType;

  String? get body => _body;

  String? get responseType => _responseType;

  String get baseURL => '$_scheme://$_host/';

  HttpClient? _httpClient;

  /// Returns [HttpClient]. Instantiates one if is null.
  HttpClient? get httpClient {
    _httpClient ??= HttpClient(baseURL);
    return _httpClient;
  }

  /// Does the request.
  Future<dynamic> doRequest() {
    return doRequestWithClient(httpClient!);
  }

  /// Does the request using parameter [httpClient].
  Future<dynamic> doRequestWithClient(HttpClient httpClient) async {
    HttpResponse httpResponse;
    if (httpCache != null) {
      httpResponse = await httpCache!.request(httpClient, httpMethod, path,
          queryParameters: _parameters, body: _body, contentType: bodyType);
    } else {
      httpResponse = await httpClient.request(httpMethod, path,
          parameters: _parameters, body: _body, contentType: bodyType);
    }

    return _processResponse(httpResponse, httpClient);
  }

  /// Process the response and handles JSON and JSONPaging.
  dynamic _processResponse(HttpResponse httpResponse, HttpClient client) {
    if (!httpResponse.isOK) return null;

    if (_responseType == 'json') {
      return httpResponse.json;
    } else if (_responseType == 'jsonpaging' ||
        _responseType == 'json_paging') {
      return _asJSONPaging(client, httpResponse);
    }

    if (httpResponse.isBodyTypeJSON) {
      var asJSONPaging = _asJSONPaging(client, httpResponse);
      return asJSONPaging ?? httpResponse.json;
    }

    return httpResponse.bodyAsString;
  }

  JSONPaging? _asJSONPaging(HttpClient client, HttpResponse httpResponse) {
    var paging = httpResponse.asJSONPaging;
    if (paging == null) return null;

    paging.pagingRequester = (page) async {
      var method = httpResponse.method;
      var url = paging.pagingRequestURL(httpResponse.requestedURL, page);

      if (httpCache != null) {
        var httpResponse2 =
            await httpCache!.requestURL(client, method, url.toString());
        return _asJSONPaging(client, httpResponse2);
      } else {
        var httpResponse2 = await client.requestURL(method, url.toString());
        return _asJSONPaging(client, httpResponse2);
      }
    };

    return paging;
  }
}
