import 'dart:typed_data';

extension ListExtension on List<int> {
  void copyWithin(int target, int start, int end) {
    for (var k = start, i = target; k < end; k++, i++) {
      this[i] = this[k];
    }
  }
}

List<int> createInt32List(int length, [int value]) {
  final data = Int32List(length);

  if (value != null) {
    data.fillRange(0, data.length, value);
  }

  return data;
}

List<int> createInt16List(int length, [int value]) {
  // TODO: Int16 quando "triple shift" for implementado!
  final data = Uint16List(length);

  if (value != null) {
    data.fillRange(0, data.length, value);
  }

  return data;
}

List<int> createInt8List(int length, [int value]) {
  final data = Int8List(length);

  if (value != null) {
    data.fillRange(0, data.length, value);
  }

  return data;
}

List<int> createInt32ListFromList(List<int> data) {
  return Int32List.fromList(data);
}

List<int> createInt16ListFromList(List<int> data) {
  return Int16List.fromList(data);
}

List<int> createInt8ListFromList(List<int> data) {
  return Int8List.fromList(data);
}
