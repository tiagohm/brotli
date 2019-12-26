import 'dart:convert';

import 'package:brotli/src/decode.dart';

/// The [BrotliCodec] encodes raw bytes to Brotli compressed bytes and decodes Brotli
/// compressed bytes to raw bytes.
class BrotliCodec extends Codec<List<int>, List<int>> {
  const BrotliCodec();

  /// Returns the [BrotliDecoder].
  @override
  Converter<List<int>, List<int>> get decoder => const BrotliDecoder();

  @override
  Converter<List<int>, List<int>> get encoder =>
      throw UnsupportedError('Cannot encode with codec: Brotli');

  /// Decodes [encoded] data to String.
  String decodeToString(List<int> encoded) {
    return String.fromCharCodes(decoder.convert(encoded));
  }
}

/// Converts Brotli compressed bytes to raw bytes.
class BrotliDecoder extends Converter<List<int>, List<int>> {
  const BrotliDecoder();

  @override
  List<int> convert(List<int> input) {
    return decode(input);
  }
}
