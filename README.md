# Brotli

Brotli decoder for Dart.

### Installation

In `pubspec.yaml` add the following dependency:

```yaml
dependencies:
  brotli: ^0.1.0
```

### Example

```dart
import 'dart:io';

import 'package:brotli/brotli.dart';

const codec = BrotliCodec();

void main() {
  final output = codec.decodeToString(File("./brotli.br").readAsBytesSync());
  print(output);
}
```
