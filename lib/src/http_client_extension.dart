import 'dart:convert';
import 'dart:typed_data';

extension ListIntExtension on List<int> {
  Uint8List toUint8List() {
    var self = this;
    if (self is Uint8List) return self;
    return Uint8List.fromList(this);
  }

  ByteBuffer toByteBuffer() {
    var self = this;
    if (self is TypedData) {
      return (self as TypedData).buffer;
    } else {
      return toUint8List().buffer;
    }
  }

  String decodeUTF8() => utf8.decode(this);

  String decodeLATIN1() => latin1.decode(this);

  String decode({bool tryUTF8 = true}) {
    if (tryUTF8) {
      try {
        return decodeUTF8();
      } catch (_) {
        return decodeLATIN1();
      }
    } else {
      return decodeLATIN1();
    }
  }
}

extension StringExtension on String {
  Uint8List toUint8List({Encoding? encoding}) =>
      (encoding ?? utf8).encode(this).toUint8List();

  ByteBuffer toByteBuffer({Encoding? encoding}) =>
      toUint8List(encoding: encoding).buffer;
}
