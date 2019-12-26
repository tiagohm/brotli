import 'dart:convert';

import 'package:brotli/src/decode.dart';

class BrotliCodec extends Encoding {
  const BrotliCodec();

  @override
  Converter<List<int>, String> get decoder => const BrotliDecoder();

  @override
  Converter<String, List<int>> get encoder =>
      throw UnsupportedError('Cannot encode with codec: Brotli');

  @override
  String get name => 'br';
}

class BrotliDecoder extends Converter<List<int>, String> {
  const BrotliDecoder();

  @override
  String convert(List<int> input) {
    return String.fromCharCodes(decode(input));
  }
}
