# Brotli

![Pub Version](https://img.shields.io/pub/v/brotli?style=flat-square)

Pure Dart Brotli decoder.

## Installation

In `pubspec.yaml` add the following dependency:

```yaml
dependencies:
  brotli: ^0.5.0
```

## Example

```dart
import 'dart:io';

import 'package:brotli/brotli.dart';

void main() {
  final output = brotli.decodeToString(File("./brotli.br").readAsBytesSync());
  print(output);
}
```
