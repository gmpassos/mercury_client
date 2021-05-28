import 'package:mercury_client/mercury_client.dart';

void main() async {
  print('------------------------------------------------');

  var client = HttpClient('https://www.google.com/');

  // GET: https://www.google.com/search?q=mercury_client
  var response =
      await client.get('search', parameters: {'q': 'mercury_client'});

  if (response.isOK) {
    var body = response.bodyAsString!;
    var ok = body.contains('<html');
    print('Request OK: $ok');
    print(response);
    print('Body Type: ${response.bodyType}\n');
    print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
    print(body);
    print('>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>\n');
  } else {
    print('Response Error!');
    print(response);
  }

  print('------------------------------------------------');

  var responsePost =
      await client.post('search', parameters: {'q': 'mercury_client'});
  assert(responsePost.isError);

  print('Google rejects POST requests!');
  print(responsePost);

  print('------------------------------------------------');

  var cache = HttpCache(verbose: true);

  {
    var response =
        await cache.get(client, 'search', parameters: {'q': 'mercury_client'});

    var status = response.status;
    var title = _catchTitle(response);

    print('Cached Request 1> status: $status ; title: $title > $cache');
  }

  {
    var response =
        await cache.get(client, 'search', parameters: {'q': 'mercury_client'});

    var status = response.status;
    var title = _catchTitle(response);

    print('Cached Request 2> status: $status ; title: $title > $cache');
  }

  {
    var client = HttpClient('https://www.google.com/');

    var response =
        await cache.get(client, 'searchX', parameters: {'q': 'mercury_client'});

    var status = response.status;

    print('Cached Request 3> status: $status > $cache');
  }

  print('------------------------------------------------\n');

  print('By!');
}

String? _catchTitle(HttpResponse response) {
  return RegExp(r'<title>\s*(.*?)\s*<')
      .firstMatch(response.bodyAsString!)!
      .group(1);
}
