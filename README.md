# Brotli

Brotli decoder for Dart.

### Installation

In `pubspec.yaml` add the following dependency:

```yaml
dependencies:
  brotli: ^0.2.1
```

### Example

```dart
import 'dart:io';

import 'package:brotli/brotli.dart';

void main() {
  final output = brotli.decodeToString(File("./brotli.br").readAsBytesSync());
  print(output);
}
```
