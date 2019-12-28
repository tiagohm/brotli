class BrotliException implements Exception {
  final String message;

  const BrotliException(this.message);

  @override
  String toString() {
    return message;
  }
}
