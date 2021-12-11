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
}

extension StringExtension on String {
  Uint8List toUint8List() => utf8.encode(this).toUint8List();

  ByteBuffer toByteBuffer() => toUint8List().buffer;
}
