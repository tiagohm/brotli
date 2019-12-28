import 'dart:io';

import 'package:brotli/brotli.dart';

void main() {
  brotli.decodeToString(File('./brotli.br').readAsBytesSync());
}
