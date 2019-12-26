class InputStream {
  final List<int> data;
  int offset;

  InputStream(
    this.data, {
    this.offset = 0,
  });
}
