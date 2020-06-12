import 'package:mercury_client/mercury_client.dart';

void main() async {
  print('------------------------------------------------');

  var client = HttpClient('https://www.google.com/');

  // GET: https://www.google.com/search?q=mercury_client
  var response =
      await client.get('search', parameters: {'q': 'mercury_client'});

  if (response.isOK) {
    var ok = response.body.contains('<html');
    print('Request OK: $ok');
    print(response);
    print('Body Type: ${response.bodyType}\n');
    print('<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<');
    print(response.body);
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

  print('------------------------------------------------\n');

  print('By!');
}
