import 'dart:convert';
import 'dart:typed_data';

extension ListIntExtension on List<int> {
  Uint8List toUint8List() {
    var self = this;
    if (self is Uint8List) return self;
    return Uint8List.fromList(this);
  }

  /// The bytes of this list as a [ByteBuffer].
  ///
  /// The [ByteBuffer] of a [Uint8List] is returned only when the list views
  /// all of it: a view of a part of a buffer (`Uint8List.sublistView`) is
  /// copied, otherwise its buffer would also hold the bytes outside the view.
  ByteBuffer toByteBuffer() {
    var self = this;
    if (self is Uint8List &&
        self.offsetInBytes == 0 &&
        self.lengthInBytes == self.buffer.lengthInBytes) {
      return self.buffer;
    } else {
      return Uint8List.fromList(this).buffer;
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
  Uint8List toUint8List({Encoding? encoding}) {
    try {
      return (encoding ?? utf8).encode(this).toUint8List();
    } catch (_) {
      if (identical(encoding, utf8)) {
        return latin1.encode(this).toUint8List();
      } else {
        return utf8.encode(this).toUint8List();
      }
    }
  }

  ByteBuffer toByteBuffer({Encoding? encoding}) =>
      toUint8List(encoding: encoding).buffer;
}
