import 'dart:io';

import 'package:brotli/brotli.dart';

const codec = BrotliCodec();

void main() {
  final output = codec.decodeToString(File('./brotli.br').readAsBytesSync());
  print(output);
}
