import 'dart:math';

import 'package:brotli/src/command_lookup.dart';
import 'package:brotli/src/dictionary.dart';
import 'package:brotli/src/input_stream.dart';
import 'package:brotli/src/lookup.dart';
import 'package:brotli/src/state.dart';
import 'package:brotli/src/transforms.dart';
import 'package:brotli/src/helper.dart';

final _maxHuffmanTableSize = createInt16ListFromList([
  256,
  402,
  436,
  468,
  500,
  534,
  566,
  598,
  630,
  662,
  694,
  726,
  758,
  790,
  822,
  854,
  886,
  920,
  952,
  984,
  1016,
  1048,
  1080,
]);
final _codeLengthCodeOrder = createInt32ListFromList([
  1,
  2,
  3,
  4,
  0,
  5,
  17,
  6,
  16,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
]);
final _distanceShortCodeIndexOffset = createInt8ListFromList([
  0,
  3,
  2,
  1,
  0,
  0,
  0,
  0,
  0,
  0,
  3,
  3,
  3,
  3,
  3,
  3,
]);
final _distanceShortCodeValueOffset = createInt8ListFromList([
  0,
  0,
  0,
  0,
  -1,
  1,
  -2,
  2,
  -3,
  3,
  -1,
  1,
  -2,
  2,
  -3,
  3,
]);
final _fixedTable = createInt32ListFromList([
  0x020000,
  0x020004,
  0x020003,
  0x030002,
  0x020000,
  0x020004,
  0x020003,
  0x040001,
  0x020000,
  0x020004,
  0x020003,
  0x030002,
  0x020000,
  0x020004,
  0x020003,
  0x040005,
]);
final _dictionaryOffsetsByLength = createInt32ListFromList([
  0,
  0,
  0,
  0,
  0,
  4096,
  9216,
  21504,
  35840,
  44032,
  53248,
  63488,
  74752,
  87040,
  93696,
  100864,
  104704,
  106752,
  108928,
  113536,
  115968,
  118528,
  119872,
  121280,
  122016,
]);
final _dictionarySizeBitsByLength = createInt8ListFromList([
  0,
  0,
  0,
  0,
  10,
  10,
  11,
  11,
  10,
  10,
  10,
  10,
  10,
  9,
  9,
  8,
  7,
  7,
  8,
  7,
  7,
  6,
  6,
  5,
  5,
]);
final _blockLengthOffset = createInt16ListFromList([
  1,
  5,
  9,
  13,
  17,
  25,
  33,
  41,
  49,
  65,
  81,
  97,
  113,
  145,
  177,
  209,
  241,
  305,
  369,
  497,
  753,
  1265,
  2289,
  4337,
  8433,
  16625,
]);
final _blockLengthNBits = createInt8ListFromList([
  2,
  2,
  2,
  2,
  3,
  3,
  3,
  3,
  4,
  4,
  4,
  4,
  5,
  5,
  5,
  5,
  6,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  24,
]);

int _log2floor(int i) {
  var result = -1;
  var step = 16;

  while (step > 0) {
    if ((i >> step) != 0) {
      result += step;
      i = i >> step;
    }

    step = step >> 1;
  }

  return result + i;
}

int _calculateDistanceAlphabetSize(
  int npostfix,
  int ndirect,
  int maxndistbits,
) {
  return 16 + ndirect + 2 * (maxndistbits << npostfix);
}

int _calculateDistanceAlphabetLimit(
  int maxDistance,
  int npostfix,
  int ndirect,
) {
  if (maxDistance < ndirect + (2 << npostfix)) {
    throw 'maxDistance is too small';
  }

  final offset = ((maxDistance - ndirect) >> npostfix) + 4;
  final ndistbits = _log2floor(offset) - 1;
  final group = ((ndistbits - 1) << 1) | ((offset >> ndistbits) & 1);

  return ((group - 1) << npostfix) + (1 << npostfix) + ndirect + 16;
}

int _decodeWindowBits(s) {
  final largeWindowEnabled = s.isLargeWindow;

  s.isLargeWindow = 0;

  if (s.bitOffset >= 16) {
    s.accumulator =
        (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
    s.bitOffset -= 16;
  }

  if (_readFewBits(s, 1) == 0) {
    return 16;
  }

  var n = _readFewBits(s, 3);

  if (n != 0) {
    return 17 + n;
  }

  n = _readFewBits(s, 3);

  if (n != 0) {
    if (n == 1) {
      if (largeWindowEnabled == 0) {
        return -1;
      }

      s.isLargeWindow = 1;

      if (_readFewBits(s, 1) == 1) {
        return -1;
      }

      n = _readFewBits(s, 6);

      if (n < 10 || n > 30) {
        return -1;
      }

      return n;
    } else {
      return 8 + n;
    }
  }

  return 17;
}

void _initState(
  State s,
  InputStream input,
) {
  if (s.runningState != 0) {
    throw 'State MUST be uninitialized';
  }

  s.blockTrees = createInt32List(3091, 0);
  s.blockTrees[0] = 7;
  s.distRbIdx = 3;
  final maxDistanceAlphabetLimit =
      _calculateDistanceAlphabetLimit(0x7FFFFFFC, 3, 15 << 3);
  s.distExtraBits = createInt8List(maxDistanceAlphabetLimit, 0);
  s.distOffset = createInt32List(maxDistanceAlphabetLimit, 0);
  s.input = input;

  _initBitReader(s);

  s.runningState = 1;
}

void _close(s) {
  if (s.runningState == 0) {
    throw 'State must be initialized';
  }

  if (s.runningState == 11) {
    return;
  }

  s.runningState = 11;

  if (s.input != null) {
    _closeInput(s.input);
    s.input = null;
  }
}

int _decodeVarLenUnsignedByte(State s) {
  if (s.bitOffset >= 16) {
    s.accumulator =
        (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
    s.bitOffset -= 16;
  }
  if (_readFewBits(s, 1) != 0) {
    final n = _readFewBits(s, 3);

    if (n == 0) {
      return 1;
    } else {
      return _readFewBits(s, n) + (1 << n);
    }
  }

  return 0;
}

void _decodeMetaBlockLength(State s) {
  if (s.bitOffset >= 16) {
    s.accumulator =
        (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
    s.bitOffset -= 16;
  }

  s.inputEnd = _readFewBits(s, 1);
  s.metaBlockLength = 0;
  s.isUncompressed = 0;
  s.isMetadata = 0;

  if ((s.inputEnd != 0) && _readFewBits(s, 1) != 0) {
    return;
  }

  final sizeNibbles = _readFewBits(s, 2) + 4;

  if (sizeNibbles == 7) {
    s.isMetadata = 1;

    if (_readFewBits(s, 1) != 0) {
      throw 'Corrupted reserved bit';
    }

    final sizeBytes = _readFewBits(s, 2);

    if (sizeBytes == 0) {
      return;
    }

    for (var i = 0; i < sizeBytes; i++) {
      if (s.bitOffset >= 16) {
        s.accumulator =
            (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
        s.bitOffset -= 16;
      }

      final bits = _readFewBits(s, 8);

      if (bits == 0 && i + 1 == sizeBytes && sizeBytes > 1) {
        throw 'Exuberant nibble';
      }

      s.metaBlockLength |= bits << (i * 8);
    }
  } else {
    for (var i = 0; i < sizeNibbles; i++) {
      if (s.bitOffset >= 16) {
        s.accumulator =
            (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
        s.bitOffset -= 16;
      }

      final bits = _readFewBits(s, 4);

      if (bits == 0 && i + 1 == sizeNibbles && sizeNibbles > 4) {
        throw 'Exuberant nibble';
      }
      s.metaBlockLength |= bits << (i * 4);
    }
  }

  s.metaBlockLength++;

  if (s.inputEnd == 0) {
    s.isUncompressed = _readFewBits(s, 1);
  }
}

int _readSymbol(
  List<int> tableGroup,
  int tableIdx,
  State s,
) {
  var offset = tableGroup[tableIdx];
  final val = (s.accumulator >> s.bitOffset);
  offset += val & 0xFF;
  final bits = tableGroup[offset] >> 16;
  final sym = tableGroup[offset] & 0xFFFF;

  if (bits <= 8) {
    s.bitOffset += bits;
    return sym;
  }

  offset += sym;

  final mask = (1 << bits) - 1;
  offset += (val & mask) >> 8;
  s.bitOffset += ((tableGroup[offset] >> 16) + 8);

  return tableGroup[offset] & 0xFFFF;
}

int _readBlockLength(
  List<int> tableGroup,
  int tableIdx,
  State s,
) {
  if (s.bitOffset >= 16) {
    s.accumulator =
        (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
    s.bitOffset -= 16;
  }

  final code = _readSymbol(tableGroup, tableIdx, s);
  final n = _blockLengthNBits[code];

  if (s.bitOffset >= 16) {
    s.accumulator =
        (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
    s.bitOffset -= 16;
  }

  return _blockLengthOffset[code] +
      ((n <= 16) ? _readFewBits(s, n) : _readManyBits(s, n));
}

void _moveToFront(
  List<int> v,
  int index,
) {
  final value = v[index];

  for (; index > 0; index--) {
    v[index] = v[index - 1];
  }

  v[0] = value;
}

void _inverseMoveToFrontTransform(
  List<int> v,
  int length,
) {
  final mtf = createInt32List(256, 0);

  for (var i = 0; i < 256; i++) {
    mtf[i] = i;
  }

  for (var i = 0; i < length; i++) {
    final index = v[i] & 0xFF;

    v[i] = mtf[index];

    if (index != 0) {
      _moveToFront(mtf, index);
    }
  }
}

void _readHuffmanCodeLengths(
  List<int> codeLengthCodeLengths,
  int numSymbols,
  List<int> codeLengths,
  State s,
) {
  var symbol = 0;
  var prevCodeLen = 8;
  var repeat = 0;
  var repeatCodeLen = 0;
  var space = 32768;
  final table = createInt32List(32 + 1, 0);
  final tableIdx = table.length - 1;

  _buildHuffmanTable(table, tableIdx, 5, codeLengthCodeLengths, 18);

  while (symbol < numSymbols && space > 0) {
    if (s.halfOffset > 2030) {
      _doReadMoreInput(s);
    }

    if (s.bitOffset >= 16) {
      s.accumulator =
          (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
      s.bitOffset -= 16;
    }

    final p = (s.accumulator >> s.bitOffset) & 31;
    s.bitOffset += table[p] >> 16;
    final codeLen = table[p] & 0xFFFF;

    if (codeLen < 16) {
      repeat = 0;
      codeLengths[symbol++] = codeLen;
      if (codeLen != 0) {
        prevCodeLen = codeLen;
        space -= 32768 >> codeLen;
      }
    } else {
      final extraBits = codeLen - 14;
      var newLen = 0;

      if (codeLen == 16) {
        newLen = prevCodeLen;
      }

      if (repeatCodeLen != newLen) {
        repeat = 0;
        repeatCodeLen = newLen;
      }

      final oldRepeat = repeat;

      if (repeat > 0) {
        repeat -= 2;
        repeat <<= extraBits;
      }

      if (s.bitOffset >= 16) {
        s.accumulator =
            (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
        s.bitOffset -= 16;
      }

      repeat += _readFewBits(s, extraBits) + 3;
      final repeatDelta = repeat - oldRepeat;

      if (symbol + repeatDelta > numSymbols) {
        throw 'symbol + repeatDelta > numSymbols';
      }

      for (var i = 0; i < repeatDelta; i++) {
        codeLengths[symbol++] = repeatCodeLen;
      }

      if (repeatCodeLen != 0) {
        space -= repeatDelta << (15 - repeatCodeLen);
      }
    }
  }

  if (space != 0) {
    throw 'Unused space';
  }

  codeLengths.fillRange(symbol, numSymbols, 0);
}

void _checkDupes(
  List<int> symbols,
  int length,
) {
  for (var i = 0; i < length - 1; i++) {
    for (var j = i + 1; j < length; j++) {
      if (symbols[i] == symbols[j]) {
        throw 'Duplicate simple Huffman code symbol';
      }
    }
  }
}

int _readSimpleHuffmanCode(
  int alphabetSizeMax,
  int alphabetSizeLimit,
  List<int> tableGroup,
  int tableIdx,
  State s,
) {
  final codeLengths = createInt32List(alphabetSizeLimit, 0);
  final symbols = createInt32List(4, 0);
  final maxBits = 1 + _log2floor(alphabetSizeMax - 1);
  final numSymbols = _readFewBits(s, 2) + 1;

  for (var i = 0; i < numSymbols; i++) {
    if (s.bitOffset >= 16) {
      s.accumulator =
          (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
      s.bitOffset -= 16;
    }

    final symbol = _readFewBits(s, maxBits);

    if (symbol >= alphabetSizeLimit) {
      throw "Can't readHuffmanCode";
    }

    symbols[i] = symbol;
  }

  _checkDupes(symbols, numSymbols);

  var histogramId = numSymbols;

  if (numSymbols == 4) {
    histogramId += _readFewBits(s, 1);
  }

  switch (histogramId) {
    case 1:
      codeLengths[symbols[0]] = 1;
      break;
    case 2:
      codeLengths[symbols[0]] = 1;
      codeLengths[symbols[1]] = 1;
      break;
    case 3:
      codeLengths[symbols[0]] = 1;
      codeLengths[symbols[1]] = 2;
      codeLengths[symbols[2]] = 2;
      break;
    case 4:
      codeLengths[symbols[0]] = 2;
      codeLengths[symbols[1]] = 2;
      codeLengths[symbols[2]] = 2;
      codeLengths[symbols[3]] = 2;
      break;
    case 5:
      codeLengths[symbols[0]] = 1;
      codeLengths[symbols[1]] = 2;
      codeLengths[symbols[2]] = 3;
      codeLengths[symbols[3]] = 3;
      break;
    default:
      break;
  }

  return _buildHuffmanTable(
    tableGroup,
    tableIdx,
    8,
    codeLengths,
    alphabetSizeLimit,
  );
}

int _readComplexHuffmanCode(
  int alphabetSizeLimit,
  int skip,
  List<int> tableGroup,
  int tableIdx,
  State s,
) {
  final codeLengths = createInt32List(alphabetSizeLimit, 0);
  final codeLengthCodeLengths = createInt32List(18, 0);
  var space = 32;
  var numCodes = 0;

  for (var i = skip; i < 18 && space > 0; i++) {
    final codeLenIdx = _codeLengthCodeOrder[i];

    if (s.bitOffset >= 16) {
      s.accumulator =
          (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
      s.bitOffset -= 16;
    }

    final p = (s.accumulator >> s.bitOffset) & 15;
    s.bitOffset += _fixedTable[p] >> 16;
    final v = _fixedTable[p] & 0xFFFF;

    codeLengthCodeLengths[codeLenIdx] = v;

    if (v != 0) {
      space -= (32 >> v);
      numCodes++;
    }
  }

  if (space != 0 && numCodes != 1) {
    throw 'Corrupted Huffman code histogram';
  }

  _readHuffmanCodeLengths(
    codeLengthCodeLengths,
    alphabetSizeLimit,
    codeLengths,
    s,
  );

  return _buildHuffmanTable(
    tableGroup,
    tableIdx,
    8,
    codeLengths,
    alphabetSizeLimit,
  );
}

int _readHuffmanCode(
  int alphabetSizeMax,
  int alphabetSizeLimit,
  List<int> tableGroup,
  int tableIdx,
  State s,
) {
  if (s.halfOffset > 2030) {
    _doReadMoreInput(s);
  }

  if (s.bitOffset >= 16) {
    s.accumulator =
        (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
    s.bitOffset -= 16;
  }

  final simpleCodeOrSkip = _readFewBits(s, 2);

  if (simpleCodeOrSkip == 1) {
    return _readSimpleHuffmanCode(
      alphabetSizeMax,
      alphabetSizeLimit,
      tableGroup,
      tableIdx,
      s,
    );
  } else {
    return _readComplexHuffmanCode(
      alphabetSizeLimit,
      simpleCodeOrSkip,
      tableGroup,
      tableIdx,
      s,
    );
  }
}

int _decodeContextMap(
  int contextMapSize,
  List<int> contextMap,
  State s,
) {
  if (s.halfOffset > 2030) {
    _doReadMoreInput(s);
  }

  final numTrees = _decodeVarLenUnsignedByte(s) + 1;

  if (numTrees == 1) {
    contextMap.fillRange(0, contextMapSize, 0);
    return numTrees;
  }

  if (s.bitOffset >= 16) {
    s.accumulator =
        (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
    s.bitOffset -= 16;
  }

  final useRleForZeros = _readFewBits(s, 1);
  var maxRunLengthPrefix = 0;

  if (useRleForZeros != 0) {
    maxRunLengthPrefix = _readFewBits(s, 4) + 1;
  }

  final alphabetSize = numTrees + maxRunLengthPrefix;
  final tableSize = _maxHuffmanTableSize[(alphabetSize + 31) >> 5];
  final table = createInt32List(tableSize + 1, 0);
  final tableIdx = table.length - 1;

  _readHuffmanCode(alphabetSize, alphabetSize, table, tableIdx, s);

  for (var i = 0; i < contextMapSize;) {
    if (s.halfOffset > 2030) {
      _doReadMoreInput(s);
    }

    if (s.bitOffset >= 16) {
      s.accumulator =
          (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
      s.bitOffset -= 16;
    }

    final code = _readSymbol(table, tableIdx, s);

    if (code == 0) {
      contextMap[i] = 0;
      i++;
    } else if (code <= maxRunLengthPrefix) {
      if (s.bitOffset >= 16) {
        s.accumulator =
            (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
        s.bitOffset -= 16;
      }

      var reps = (1 << code) + _readFewBits(s, code);

      while (reps != 0) {
        if (i >= contextMapSize) {
          throw 'Corrupted context map';
        }

        contextMap[i] = 0;
        i++;
        reps--;
      }
    } else {
      contextMap[i] = (code - maxRunLengthPrefix);
      i++;
    }
  }

  if (s.bitOffset >= 16) {
    s.accumulator =
        (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
    s.bitOffset -= 16;
  }

  if (_readFewBits(s, 1) == 1) {
    _inverseMoveToFrontTransform(contextMap, contextMapSize);
  }

  return numTrees;
}

int _decodeBlockTypeAndLength(
  State s,
  int treeType,
  int numBlockTypes,
) {
  final ringBuffers = s.rings;
  final offset = 4 + treeType * 2;

  if (s.bitOffset >= 16) {
    s.accumulator =
        (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
    s.bitOffset -= 16;
  }

  var blockType = _readSymbol(s.blockTrees, 2 * treeType, s);
  final result = _readBlockLength(s.blockTrees, 2 * treeType + 1, s);

  if (blockType == 1) {
    blockType = ringBuffers[offset + 1] + 1;
  } else if (blockType == 0) {
    blockType = ringBuffers[offset];
  } else {
    blockType -= 2;
  }

  if (blockType >= numBlockTypes) {
    blockType -= numBlockTypes;
  }

  ringBuffers[offset] = ringBuffers[offset + 1];
  ringBuffers[offset + 1] = blockType;

  return result;
}

void _decodeLiteralBlockSwitch(s) {
  s.literalBlockLength =
      _decodeBlockTypeAndLength(s, 0, s.numLiteralBlockTypes);
  final literalBlockType = s.rings[5];
  s.contextMapSlice = literalBlockType << 6;
  s.literalTreeIdx = s.contextMap[s.contextMapSlice] & 0xFF;
  final contextMode = s.contextModes[literalBlockType];
  s.contextLookupOffset1 = contextMode << 9;
  s.contextLookupOffset2 = s.contextLookupOffset1 + 256;
}

void _decodeCommandBlockSwitch(s) {
  s.commandBlockLength =
      _decodeBlockTypeAndLength(s, 1, s.numCommandBlockTypes);
  s.commandTreeIdx = s.rings[7];
}

void _decodeDistanceBlockSwitch(s) {
  s.distanceBlockLength =
      _decodeBlockTypeAndLength(s, 2, s.numDistanceBlockTypes);
  s.distContextMapSlice = s.rings[9] << 2;
}

void _maybeReallocateRingBuffer(State s) {
  var newSize = s.maxRingBufferSize;

  if (newSize > s.expectedTotalSize) {
    final minimalNewSize = s.expectedTotalSize;

    while ((newSize >> 1) > minimalNewSize) {
      newSize >>= 1;
    }

    if ((s.inputEnd == 0) && newSize < 16384 && s.maxRingBufferSize >= 16384) {
      newSize = 16384;
    }
  }

  if (newSize <= s.ringBufferSize) {
    return;
  }

  final ringBufferSizeWithSlack = newSize + 37;
  final newBuffer = createInt8List(ringBufferSizeWithSlack, 0);

  if (s.ringBuffer.isNotEmpty) {
    newBuffer.setAll(0, s.ringBuffer.sublist(0, 0 + s.ringBufferSize));
  }

  s.ringBuffer = newBuffer;
  s.ringBufferSize = newSize;
}

void _readNextMetablockHeader(State s) {
  if (s.inputEnd != 0) {
    s.nextRunningState = 10;
    s.runningState = 12;
    return;
  }

  s.literalTreeGroup = createInt32List(0);
  s.commandTreeGroup = createInt32List(0);
  s.distanceTreeGroup = createInt32List(0);

  if (s.halfOffset > 2030) {
    _doReadMoreInput(s);
  }

  _decodeMetaBlockLength(s);

  if (s.metaBlockLength == 0 && s.isMetadata == 0) {
    return;
  }

  if (s.isUncompressed != 0 || s.isMetadata != 0) {
    _jumpToByteBoundary(s);
    s.runningState = s.isMetadata != 0 ? 5 : 6;
  } else {
    s.runningState = 3;
  }

  if (s.isMetadata != 0) {
    return;
  }

  s.expectedTotalSize += s.metaBlockLength;

  if (s.expectedTotalSize > 1 << 30) {
    s.expectedTotalSize = 1 << 30;
  }

  if (s.ringBufferSize < s.maxRingBufferSize) {
    _maybeReallocateRingBuffer(s);
  }
}

int _readMetablockPartition(
  State s,
  int treeType,
  int numBlockTypes,
) {
  var offset = s.blockTrees[2 * treeType];

  if (numBlockTypes <= 1) {
    s.blockTrees[2 * treeType + 1] = offset;
    s.blockTrees[2 * treeType + 2] = offset;
    return 1 << 28;
  }

  final blockTypeAlphabetSize = numBlockTypes + 2;

  offset += _readHuffmanCode(
    blockTypeAlphabetSize,
    blockTypeAlphabetSize,
    s.blockTrees,
    2 * treeType,
    s,
  );

  s.blockTrees[2 * treeType + 1] = offset;

  final blockLengthAlphabetSize = 26;

  offset += _readHuffmanCode(
    blockLengthAlphabetSize,
    blockLengthAlphabetSize,
    s.blockTrees,
    2 * treeType + 1,
    s,
  );

  s.blockTrees[2 * treeType + 2] = offset;

  return _readBlockLength(s.blockTrees, 2 * treeType + 1, s);
}

void _calculateDistanceLut(
  State s,
  int alphabetSizeLimit,
) {
  final distExtraBits = s.distExtraBits;
  final distOffset = s.distOffset;
  final npostfix = s.distancePostfixBits;
  final ndirect = s.numDirectDistanceCodes;
  final postfix = 1 << npostfix;
  var bits = 1;
  var half = 0;
  var i = 16;

  for (var j = 0; j < ndirect; j++) {
    distExtraBits[i] = 0;
    distOffset[i] = j + 1;
    i++;
  }

  while (i < alphabetSizeLimit) {
    final base = ndirect + ((((2 + half) << bits) - 4) << npostfix) + 1;

    for (var j = 0; j < postfix; j++) {
      distExtraBits[i] = bits;
      distOffset[i] = base + j;
      i++;
    }

    bits = bits + half;
    half = half ^ 1;
  }
}

void _readMetablockHuffmanCodesAndContextMaps(State s) {
  s.numLiteralBlockTypes = _decodeVarLenUnsignedByte(s) + 1;
  s.literalBlockLength = _readMetablockPartition(s, 0, s.numLiteralBlockTypes);
  s.numCommandBlockTypes = _decodeVarLenUnsignedByte(s) + 1;
  s.commandBlockLength = _readMetablockPartition(s, 1, s.numCommandBlockTypes);
  s.numDistanceBlockTypes = _decodeVarLenUnsignedByte(s) + 1;
  s.distanceBlockLength =
      _readMetablockPartition(s, 2, s.numDistanceBlockTypes);

  if (s.halfOffset > 2030) {
    _doReadMoreInput(s);
  }

  if (s.bitOffset >= 16) {
    s.accumulator =
        (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
    s.bitOffset -= 16;
  }

  s.distancePostfixBits = _readFewBits(s, 2);
  s.numDirectDistanceCodes = _readFewBits(s, 4) << s.distancePostfixBits;
  s.distancePostfixMask = (1 << s.distancePostfixBits) - 1;
  s.contextModes = createInt8List(s.numLiteralBlockTypes, 0);

  for (var i = 0; i < s.numLiteralBlockTypes;) {
    final limit = min(i + 96, s.numLiteralBlockTypes);

    for (; i < limit; i++) {
      if (s.bitOffset >= 16) {
        s.accumulator =
            (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
        s.bitOffset -= 16;
      }
      s.contextModes[i] = _readFewBits(s, 2);
    }

    if (s.halfOffset > 2030) {
      _doReadMoreInput(s);
    }
  }

  s.contextMap = createInt8List(s.numLiteralBlockTypes << 6, 0);

  final numLiteralTrees =
      _decodeContextMap(s.numLiteralBlockTypes << 6, s.contextMap, s);
  s.trivialLiteralContext = 1;

  for (var j = 0; j < s.numLiteralBlockTypes << 6; j++) {
    if (s.contextMap[j] != j >> 6) {
      s.trivialLiteralContext = 0;
      break;
    }
  }

  s.distContextMap = createInt8List(s.numDistanceBlockTypes << 2, 0);
  final numDistTrees = _decodeContextMap(
    s.numDistanceBlockTypes << 2,
    s.distContextMap,
    s,
  );
  s.literalTreeGroup = _decodeHuffmanTreeGroup(256, 256, numLiteralTrees, s);
  s.commandTreeGroup = _decodeHuffmanTreeGroup(
    704,
    704,
    s.numCommandBlockTypes,
    s,
  );

  var distanceAlphabetSizeMax = _calculateDistanceAlphabetSize(
    s.distancePostfixBits,
    s.numDirectDistanceCodes,
    24,
  );

  var distanceAlphabetSizeLimit = distanceAlphabetSizeMax;

  if (s.isLargeWindow == 1) {
    distanceAlphabetSizeMax = _calculateDistanceAlphabetSize(
      s.distancePostfixBits,
      s.numDirectDistanceCodes,
      62,
    );
    distanceAlphabetSizeLimit = _calculateDistanceAlphabetLimit(
      0x7FFFFFFC,
      s.distancePostfixBits,
      s.numDirectDistanceCodes,
    );
  }

  s.distanceTreeGroup = _decodeHuffmanTreeGroup(
    distanceAlphabetSizeMax,
    distanceAlphabetSizeLimit,
    numDistTrees,
    s,
  );

  _calculateDistanceLut(s, distanceAlphabetSizeLimit);

  s.contextMapSlice = 0;
  s.distContextMapSlice = 0;
  s.contextLookupOffset1 = s.contextModes[0] * 512;
  s.contextLookupOffset2 = s.contextLookupOffset1 + 256;
  s.literalTreeIdx = 0;
  s.commandTreeIdx = 0;
  s.rings[4] = 1;
  s.rings[5] = 0;
  s.rings[6] = 1;
  s.rings[7] = 0;
  s.rings[8] = 1;
  s.rings[9] = 0;
}

void _copyUncompressedData(State s) {
  final ringBuffer = s.ringBuffer;

  if (s.metaBlockLength <= 0) {
    _reload(s);
    s.runningState = 2;
    return;
  }

  final chunkLength = min(s.ringBufferSize - s.pos, s.metaBlockLength);

  _copyBytes(s, ringBuffer, s.pos, chunkLength);

  s.metaBlockLength -= chunkLength;
  s.pos += chunkLength;

  if (s.pos == s.ringBufferSize) {
    s.nextRunningState = 6;
    s.runningState = 12;
    return;
  }

  _reload(s);

  s.runningState = 2;
}

int _writeRingBuffer(State s) {
  final toWrite = min(
    s.outputLength - s.outputUsed,
    s.ringBufferBytesReady - s.ringBufferBytesWritten,
  );

  if (toWrite != 0) {
    s.output.setAll(
      s.outputOffset + s.outputUsed,
      s.ringBuffer.sublist(
          s.ringBufferBytesWritten, s.ringBufferBytesWritten + toWrite),
    );
    s.outputUsed += toWrite;
    s.ringBufferBytesWritten += toWrite;
  }

  if (s.outputUsed < s.outputLength) {
    return 1;
  } else {
    return 0;
  }
}

List<int> _decodeHuffmanTreeGroup(
  int alphabetSizeMax,
  int alphabetSizeLimit,
  int n,
  State s,
) {
  final maxTableSize = _maxHuffmanTableSize[(alphabetSizeLimit + 31) >> 5];
  final group = createInt32List(n + n * maxTableSize, 0);
  var next = n;

  for (var i = 0; i < n; i++) {
    group[i] = next;
    next += _readHuffmanCode(alphabetSizeMax, alphabetSizeLimit, group, i, s);
  }

  return group;
}

int _calculateFence(State s) {
  var result = s.ringBufferSize;

  if (s.isEager != 0) {
    result = min(
      result,
      s.ringBufferBytesWritten + s.outputLength - s.outputUsed,
    );
  }

  return result;
}

void _decompress(State s) {
  if (s.runningState == 0) {
    throw "Can't decompress until initialized";
  }

  if (s.runningState == 11) {
    throw "Can't decompress after close";
  }

  if (s.runningState == 1) {
    final windowBits = _decodeWindowBits(s);

    if (windowBits == -1) {
      throw "Invalid 'windowBits' code";
    }

    s.maxRingBufferSize = 1 << windowBits;
    s.maxBackwardDistance = s.maxRingBufferSize - 16;
    s.runningState = 2;
  }

  var fence = _calculateFence(s);
  var ringBufferMask = s.ringBufferSize - 1;
  var ringBuffer = s.ringBuffer;

  while (s.runningState != 10) {
    switch (s.runningState) {
      case 2:
        if (s.metaBlockLength < 0) {
          throw 'Invalid metablock length';
        }

        _readNextMetablockHeader(s);
        fence = _calculateFence(s);
        ringBufferMask = s.ringBufferSize - 1;
        ringBuffer = s.ringBuffer;
        continue;
      case 3:
        _readMetablockHuffmanCodesAndContextMaps(s);
        s.runningState = 4;
        continue;
      case 4:
        if (s.metaBlockLength <= 0) {
          s.runningState = 2;
          continue;
        }

        if (s.halfOffset > 2030) {
          _doReadMoreInput(s);
        }

        if (s.commandBlockLength == 0) {
          _decodeCommandBlockSwitch(s);
        }

        s.commandBlockLength--;

        if (s.bitOffset >= 16) {
          s.accumulator =
              (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
          s.bitOffset -= 16;
        }

        final cmdCode =
            _readSymbol(s.commandTreeGroup, s.commandTreeIdx, s) << 2;
        final insertAndCopyExtraBits = cmdLookup[cmdCode];
        final insertLengthOffset = cmdLookup[cmdCode + 1];
        final copyLengthOffset = cmdLookup[cmdCode + 2];

        s.distanceCode = cmdLookup[cmdCode + 3];

        if (s.bitOffset >= 16) {
          s.accumulator =
              (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
          s.bitOffset -= 16;
        }

        var extraBits = insertAndCopyExtraBits & 0xFF;

        s.insertLength = insertLengthOffset +
            ((extraBits <= 16)
                ? _readFewBits(s, extraBits)
                : _readManyBits(s, extraBits));

        if (s.bitOffset >= 16) {
          s.accumulator =
              (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
          s.bitOffset -= 16;
        }

        extraBits = insertAndCopyExtraBits >> 8;

        s.copyLength = copyLengthOffset +
            ((extraBits <= 16)
                ? _readFewBits(s, extraBits)
                : _readManyBits(s, extraBits));
        s.j = 0;
        s.runningState = 7;
        continue;
      case 7:
        if (s.trivialLiteralContext != 0) {
          while (s.j < s.insertLength) {
            if (s.halfOffset > 2030) {
              _doReadMoreInput(s);
            }

            if (s.literalBlockLength == 0) {
              _decodeLiteralBlockSwitch(s);
            }

            s.literalBlockLength--;

            if (s.bitOffset >= 16) {
              s.accumulator =
                  (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
              s.bitOffset -= 16;
            }

            ringBuffer[s.pos] = _readSymbol(
              s.literalTreeGroup,
              s.literalTreeIdx,
              s,
            );

            s.pos++;
            s.j++;

            if (s.pos >= fence) {
              s.nextRunningState = 7;
              s.runningState = 12;
              break;
            }
          }
        } else {
          var prevByte1 = ringBuffer[(s.pos - 1) & ringBufferMask] & 0xFF;
          var prevByte2 = ringBuffer[(s.pos - 2) & ringBufferMask] & 0xFF;

          while (s.j < s.insertLength) {
            if (s.halfOffset > 2030) {
              _doReadMoreInput(s);
            }

            if (s.literalBlockLength == 0) {
              _decodeLiteralBlockSwitch(s);
            }

            final literalContext = lookup[s.contextLookupOffset1 + prevByte1] |
                lookup[s.contextLookupOffset2 + prevByte2];
            final literalTreeIdx =
                s.contextMap[s.contextMapSlice + literalContext] & 0xFF;

            s.literalBlockLength--;
            prevByte2 = prevByte1;

            if (s.bitOffset >= 16) {
              s.accumulator =
                  (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
              s.bitOffset -= 16;
            }

            prevByte1 = _readSymbol(s.literalTreeGroup, literalTreeIdx, s);
            ringBuffer[s.pos] = prevByte1;
            s.pos++;
            s.j++;

            if (s.pos >= fence) {
              s.nextRunningState = 7;
              s.runningState = 12;
              break;
            }
          }
        }

        if (s.runningState != 7) {
          continue;
        }

        s.metaBlockLength -= s.insertLength;

        if (s.metaBlockLength <= 0) {
          s.runningState = 4;
          continue;
        }

        var distanceCode = s.distanceCode;

        if (distanceCode < 0) {
          s.distance = s.rings[s.distRbIdx];
        } else {
          if (s.halfOffset > 2030) {
            _doReadMoreInput(s);
          }

          if (s.distanceBlockLength == 0) {
            _decodeDistanceBlockSwitch(s);
          }

          s.distanceBlockLength--;

          if (s.bitOffset >= 16) {
            s.accumulator =
                (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
            s.bitOffset -= 16;
          }

          final distTreeIdx =
              s.distContextMap[s.distContextMapSlice + distanceCode] & 0xFF;
          distanceCode = _readSymbol(s.distanceTreeGroup, distTreeIdx, s);

          if (distanceCode < 16) {
            final index =
                (s.distRbIdx + _distanceShortCodeIndexOffset[distanceCode]) &
                    0x3;
            s.distance =
                s.rings[index] + _distanceShortCodeValueOffset[distanceCode];

            if (s.distance < 0) {
              throw 'Negative distance';
            }
          } else {
            final extraBits = s.distExtraBits[distanceCode];
            var bits;

            if (s.bitOffset + extraBits <= 32) {
              bits = _readFewBits(s, extraBits);
            } else {
              if (s.bitOffset >= 16) {
                s.accumulator = (s.shortBuffer[s.halfOffset++] << 16) |
                    (s.accumulator >> 16);
                s.bitOffset -= 16;
              }
              bits = ((extraBits <= 16)
                  ? _readFewBits(s, extraBits)
                  : _readManyBits(s, extraBits));
            }

            s.distance =
                s.distOffset[distanceCode] + (bits << s.distancePostfixBits);
          }
        }

        if (s.maxDistance != s.maxBackwardDistance &&
            s.pos < s.maxBackwardDistance) {
          s.maxDistance = s.pos;
        } else {
          s.maxDistance = s.maxBackwardDistance;
        }

        if (s.distance > s.maxDistance) {
          s.runningState = 9;
          continue;
        }

        if (distanceCode > 0) {
          s.distRbIdx = (s.distRbIdx + 1) & 0x3;
          s.rings[s.distRbIdx] = s.distance;
        }

        if (s.copyLength > s.metaBlockLength) {
          throw 'Invalid backward reference';
        }

        s.j = 0;
        s.runningState = 8;
        continue;
      case 8:
        var src = (s.pos - s.distance) & ringBufferMask;
        var dst = s.pos;
        final copyLength = s.copyLength - s.j;
        final srcEnd = src + copyLength;
        final dstEnd = dst + copyLength;

        if ((srcEnd < ringBufferMask) && (dstEnd < ringBufferMask)) {
          if (copyLength < 12 || (srcEnd > dst && dstEnd > src)) {
            for (var k = 0; k < copyLength; k += 4) {
              ringBuffer[dst++] = ringBuffer[src++];
              ringBuffer[dst++] = ringBuffer[src++];
              ringBuffer[dst++] = ringBuffer[src++];
              ringBuffer[dst++] = ringBuffer[src++];
            }
          } else {
            ringBuffer.copyWithin(dst, src, srcEnd);
          }

          s.j += copyLength;
          s.metaBlockLength -= copyLength;
          s.pos += copyLength;
        } else {
          for (; s.j < s.copyLength;) {
            ringBuffer[s.pos] =
                ringBuffer[(s.pos - s.distance) & ringBufferMask];
            s.metaBlockLength--;
            s.pos++;
            s.j++;

            if (s.pos >= fence) {
              s.nextRunningState = 8;
              s.runningState = 12;
              break;
            }
          }
        }

        if (s.runningState == 8) {
          s.runningState = 4;
        }

        continue;
      case 9:
        if (s.distance > 0x7FFFFFFC) {
          throw 'Invalid backward reference';
        }

        if (s.copyLength >= 4 && s.copyLength <= 24) {
          var offset = _dictionaryOffsetsByLength[s.copyLength];
          final wordId = s.distance - s.maxDistance - 1;
          final shift = _dictionarySizeBitsByLength[s.copyLength];
          final mask = (1 << shift) - 1;
          final wordIdx = wordId & mask;
          final transformIdx = wordId >> shift;

          offset += wordIdx * s.copyLength;

          if (transformIdx < 121) {
            final len = _transformDictionaryWord(
              ringBuffer,
              s.pos,
              dictionaryData,
              offset,
              s.copyLength,
              rfcTransforms,
              transformIdx,
            );
            s.pos += len;
            s.metaBlockLength -= len;

            if (s.pos >= fence) {
              s.nextRunningState = 4;
              s.runningState = 12;
              continue;
            }
          } else {
            throw 'Invalid backward reference';
          }
        } else {
          throw 'Invalid backward reference';
        }

        s.runningState = 4;
        continue;
      case 5:
        while (s.metaBlockLength > 0) {
          if (s.halfOffset > 2030) {
            _doReadMoreInput(s);
          }

          if (s.bitOffset >= 16) {
            s.accumulator =
                (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
            s.bitOffset -= 16;
          }

          _readFewBits(s, 8);
          s.metaBlockLength--;
        }

        s.runningState = 2;
        continue;
      case 6:
        _copyUncompressedData(s);
        continue;
      case 12:
        s.ringBufferBytesReady = min(s.pos, s.ringBufferSize);
        s.runningState = 13;
        continue;
      case 13:
        if (_writeRingBuffer(s) == 0) {
          return;
        }

        if (s.pos >= s.maxBackwardDistance) {
          s.maxDistance = s.maxBackwardDistance;
        }

        if (s.pos >= s.ringBufferSize) {
          if (s.pos > s.ringBufferSize) {
            ringBuffer.copyWithin(0, s.ringBufferSize, s.pos);
          }

          s.pos &= ringBufferMask;
          s.ringBufferBytesWritten = 0;
        }

        s.runningState = s.nextRunningState;
        continue;
      default:
        throw 'Unexpected state ${s.runningState}';
    }
  }

  if (s.runningState == 10) {
    if (s.metaBlockLength < 0) {
      throw 'Invalid metablock length';
    }

    _jumpToByteBoundary(s);
    _checkHealth(s, 1);
  }
}

int _transformDictionaryWord(
  List<int> dst,
  int dstOffset,
  List<int> src,
  int srcOffset,
  int len,
  Transforms transforms,
  int transformIndex,
) {
  var offset = dstOffset;
  final triplets = transforms.triplets;
  final prefixSuffixStorage = transforms.prefixSuffixStorage;
  final prefixSuffixHeads = transforms.prefixSuffixHeads;
  final transformOffset = 3 * transformIndex;
  final prefixIdx = triplets[transformOffset];
  final transformType = triplets[transformOffset + 1];
  final suffixIdx = triplets[transformOffset + 2];
  var prefix = prefixSuffixHeads[prefixIdx];
  final prefixEnd = prefixSuffixHeads[prefixIdx + 1];
  var suffix = prefixSuffixHeads[suffixIdx];
  final suffixEnd = prefixSuffixHeads[suffixIdx + 1];
  var omitFirst = transformType - 11;
  var omitLast = transformType - 0;

  if (omitFirst < 1 || omitFirst > 9) {
    omitFirst = 0;
  }

  if (omitLast < 1 || omitLast > 9) {
    omitLast = 0;
  }

  while (prefix != prefixEnd) {
    dst[offset++] = prefixSuffixStorage[prefix++];
  }

  if (omitFirst > len) {
    omitFirst = len;
  }

  srcOffset += omitFirst;
  len -= omitFirst;
  len -= omitLast;

  var i = len;

  while (i > 0) {
    dst[offset++] = src[srcOffset++];
    i--;
  }

  if (transformType == 10 || transformType == 11) {
    var uppercaseOffset = offset - len;

    if (transformType == 10) {
      len = 1;
    }

    while (len > 0) {
      final c0 = dst[uppercaseOffset] & 0xFF;

      if (c0 < 0xC0) {
        if (c0 >= 97 && c0 <= 122) {
          dst[uppercaseOffset] ^= 32;
        }
        uppercaseOffset += 1;
        len -= 1;
      } else if (c0 < 0xE0) {
        dst[uppercaseOffset + 1] ^= 32;
        uppercaseOffset += 2;
        len -= 2;
      } else {
        dst[uppercaseOffset + 2] ^= 5;
        uppercaseOffset += 3;
        len -= 3;
      }
    }
  } else if (transformType == 21 || transformType == 22) {
    var shiftOffset = offset - len;
    final param = transforms.params[transformIndex];
    var scalar = (param & 0x7FFF) + (0x1000000 - (param & 0x8000));

    while (len > 0) {
      var step = 1;
      final c0 = dst[shiftOffset] & 0xFF;

      if (c0 < 0x80) {
        scalar += c0;
        dst[shiftOffset] = (scalar & 0x7F);
      } else if (c0 < 0xC0) {
      } else if (c0 < 0xE0) {
        if (len >= 2) {
          final c1 = dst[shiftOffset + 1];

          scalar += (c1 & 0x3F) | ((c0 & 0x1F) << 6);
          dst[shiftOffset] = (0xC0 | ((scalar >> 6) & 0x1F));
          dst[shiftOffset + 1] = ((c1 & 0xC0) | (scalar & 0x3F));

          step = 2;
        } else {
          step = len;
        }
      } else if (c0 < 0xF0) {
        if (len >= 3) {
          final c1 = dst[shiftOffset + 1];
          final c2 = dst[shiftOffset + 2];

          scalar += (c2 & 0x3F) | ((c1 & 0x3F) << 6) | ((c0 & 0x0F) << 12);

          dst[shiftOffset] = (0xE0 | ((scalar >> 12) & 0x0F));
          dst[shiftOffset + 1] = ((c1 & 0xC0) | ((scalar >> 6) & 0x3F));
          dst[shiftOffset + 2] = ((c2 & 0xC0) | (scalar & 0x3F));

          step = 3;
        } else {
          step = len;
        }
      } else if (c0 < 0xF8) {
        if (len >= 4) {
          final c1 = dst[shiftOffset + 1];
          final c2 = dst[shiftOffset + 2];
          final c3 = dst[shiftOffset + 3];

          scalar += (c3 & 0x3F) |
              ((c2 & 0x3F) << 6) |
              ((c1 & 0x3F) << 12) |
              ((c0 & 0x07) << 18);

          dst[shiftOffset] = (0xF0 | ((scalar >> 18) & 0x07));
          dst[shiftOffset + 1] = ((c1 & 0xC0) | ((scalar >> 12) & 0x3F));
          dst[shiftOffset + 2] = ((c2 & 0xC0) | ((scalar >> 6) & 0x3F));
          dst[shiftOffset + 3] = ((c3 & 0xC0) | (scalar & 0x3F));

          step = 4;
        } else {
          step = len;
        }
      }

      shiftOffset += step;
      len -= step;

      if (transformType == 21) {
        len = 0;
      }
    }
  }

  while (suffix != suffixEnd) {
    dst[offset++] = prefixSuffixStorage[suffix++];
  }

  return offset - dstOffset;
}

int _getNextKey(
  int key,
  int len,
) {
  var step = 1 << (len - 1);

  while ((key & step) != 0) {
    step >>= 1;
  }

  return (key & (step - 1)) + step;
}

void _replicateValue(
  List<int> table,
  int offset,
  int step,
  int end,
  int item,
) {
  do {
    end -= step;
    table[offset + end] = item;
  } while (end > 0);
}

int _nextTableBitSize(
  List<int> count,
  int len,
  int rootBits,
) {
  var left = 1 << (len - rootBits);

  while (len < 15) {
    left -= count[len];
    if (left <= 0) {
      break;
    }
    len++;
    left <<= 1;
  }

  return len - rootBits;
}

int _buildHuffmanTable(
  List<int> tableGroup,
  int tableIdx,
  int rootBits,
  List<int> codeLengths,
  int codeLengthsSize,
) {
  final tableOffset = tableGroup[tableIdx];
  int key;
  final sorted = createInt32List(codeLengthsSize, 0);
  final count = createInt32List(16, 0);
  final offset = createInt32List(16, 0);
  int symbol;

  for (symbol = 0; symbol < codeLengthsSize; symbol++) {
    count[codeLengths[symbol]]++;
  }

  offset[1] = 0;

  for (var len = 1; len < 15; len++) {
    offset[len + 1] = offset[len] + count[len];
  }

  for (symbol = 0; symbol < codeLengthsSize; symbol++) {
    if (codeLengths[symbol] != 0) {
      sorted[offset[codeLengths[symbol]]++] = symbol;
    }
  }

  var tableBits = rootBits;
  var tableSize = 1 << tableBits;
  var totalSize = tableSize;

  if (offset[15] == 1) {
    for (key = 0; key < totalSize; key++) {
      tableGroup[tableOffset + key] = sorted[0];
    }
    return totalSize;
  }

  key = 0;
  symbol = 0;

  for (var len = 1, step = 2; len <= rootBits; len++, step <<= 1) {
    for (; count[len] > 0; count[len]--) {
      _replicateValue(tableGroup, tableOffset + key, step, tableSize,
          len << 16 | sorted[symbol++]);
      key = _getNextKey(key, len);
    }
  }
  final mask = totalSize - 1;
  var low = -1;
  var currentOffset = tableOffset;

  for (var len = rootBits + 1, step = 2; len <= 15; len++, step <<= 1) {
    for (; count[len] > 0; count[len]--) {
      if ((key & mask) != low) {
        currentOffset += tableSize;
        tableBits = _nextTableBitSize(count, len, rootBits);
        tableSize = 1 << tableBits;
        totalSize += tableSize;
        low = key & mask;
        tableGroup[tableOffset + low] =
            (tableBits + rootBits) << 16 | (currentOffset - tableOffset - low);
      }

      _replicateValue(
        tableGroup,
        currentOffset + (key >> rootBits),
        step,
        tableSize,
        (len - rootBits) << 16 | sorted[symbol++],
      );

      key = _getNextKey(key, len);
    }
  }
  return totalSize;
}

void _doReadMoreInput(State s) {
  if (s.endOfStreamReached != 0) {
    if (_halfAvailable(s) >= -2) {
      return;
    }

    throw 'No more input';
  }

  final readOffset = s.halfOffset << 1;
  var bytesInBuffer = 4096 - readOffset;
  s.byteBuffer.copyWithin(0, readOffset, 4096);
  s.halfOffset = 0;

  while (bytesInBuffer < 4096) {
    final spaceLeft = 4096 - bytesInBuffer;
    final len = _readInput(s.input, s.byteBuffer, bytesInBuffer, spaceLeft);

    if (len <= 0) {
      s.endOfStreamReached = 1;
      s.tailBytes = bytesInBuffer;
      bytesInBuffer += 1;
      break;
    }

    bytesInBuffer += len;
  }

  _bytesToNibbles(s, bytesInBuffer);
}

void _checkHealth(
  State s,
  int endOfStream,
) {
  if (s.endOfStreamReached == 0) {
    return;
  }
  final byteOffset = (s.halfOffset << 1) + ((s.bitOffset + 7) >> 3) - 4;
  if (byteOffset > s.tailBytes) {
    throw 'Read after end';
  }
  if ((endOfStream != 0) && (byteOffset != s.tailBytes)) {
    throw 'Unused bytes after end';
  }
}

int _readFewBits(
  State s,
  int n,
) {
  final val = (s.accumulator >> s.bitOffset) & ((1 << n) - 1);
  s.bitOffset += n;
  return val;
}

int _readManyBits(State s, int n) {
  final low = _readFewBits(s, 16);
  s.accumulator = (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
  s.bitOffset -= 16;
  return low | (_readFewBits(s, n - 16) << 16);
}

void _initBitReader(State s) {
  s.byteBuffer = createInt8List(4160, 0);
  s.accumulator = 0;
  s.shortBuffer = createInt16List(2080, 0);
  s.bitOffset = 32;
  s.halfOffset = 2048;
  s.endOfStreamReached = 0;
  _prepare(s);
}

void _prepare(State s) {
  if (s.halfOffset > 2030) {
    _doReadMoreInput(s);
  }

  _checkHealth(s, 0);

  s.accumulator = (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
  s.bitOffset -= 16;
  s.accumulator = (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
  s.bitOffset -= 16;
}

void _reload(State s) {
  if (s.bitOffset == 32) {
    _prepare(s);
  }
}

void _jumpToByteBoundary(State s) {
  final padding = (32 - s.bitOffset) & 7;

  if (padding != 0) {
    final paddingBits = _readFewBits(s, padding);

    if (paddingBits != 0) {
      throw 'Corrupted padding bits';
    }
  }
}

int _halfAvailable(State s) {
  var limit = 2048;

  if (s.endOfStreamReached != 0) {
    limit = (s.tailBytes + 1) >> 1;
  }

  return limit - s.halfOffset;
}

void _copyBytes(
  State s,
  List<int> data,
  int offset,
  int length,
) {
  if ((s.bitOffset & 7) != 0) {
    throw 'Unaligned copyBytes';
  }

  while ((s.bitOffset != 32) && (length != 0)) {
    data[offset++] = (s.accumulator >> s.bitOffset);
    s.bitOffset += 8;
    length--;
  }

  if (length == 0) {
    return;
  }

  final copyNibbles = min(_halfAvailable(s), length >> 1);

  if (copyNibbles > 0) {
    final readOffset = s.halfOffset << 1;
    final delta = copyNibbles << 1;
    data.setAll(offset, s.byteBuffer.sublist(readOffset, readOffset + delta));
    offset += delta;
    length -= delta;
    s.halfOffset += copyNibbles;
  }

  if (length == 0) {
    return;
  }

  if (_halfAvailable(s) > 0) {
    if (s.bitOffset >= 16) {
      s.accumulator =
          (s.shortBuffer[s.halfOffset++] << 16) | (s.accumulator >> 16);
      s.bitOffset -= 16;
    }

    while (length != 0) {
      data[offset++] = (s.accumulator >> s.bitOffset);
      s.bitOffset += 8;
      length--;
    }

    _checkHealth(s, 0);
    return;
  }

  while (length > 0) {
    final len = _readInput(s.input, data, offset, length);

    if (len == -1) {
      throw 'Unexpected end of input';
    }

    offset += len;
    length -= len;
  }
}

void _bytesToNibbles(
  State s,
  int byteLen,
) {
  final byteBuffer = s.byteBuffer;
  final halfLen = byteLen >> 1;
  final shortBuffer = s.shortBuffer;

  for (var i = 0; i < halfLen; i++) {
    shortBuffer[i] =
        ((byteBuffer[i * 2] & 0xFF) | ((byteBuffer[(i * 2) + 1] & 0xFF) << 8));
  }
}

int _readInput(
  InputStream src,
  List<int> dst,
  int offset,
  int length,
) {
  if (src == null) return -1;

  final end = min(src.offset + length, src.data.length);
  final bytesRead = end - src.offset;

  dst.setAll(offset, src.data.sublist(src.offset, end));
  src.offset += bytesRead;

  return bytesRead;
}

int _closeInput(InputStream src) {
  return 0;
}

List<int> decode(List<int> bytes) {
  final s = State();

  _initState(s, InputStream(bytes));

  var totalOutput = 0;
  final chunks = <List<int>>[];

  while (true) {
    final chunk = createInt8List(16384, 0); // ??

    chunks.add(chunk);

    s.output = chunk;
    s.outputOffset = 0;
    s.outputLength = 16384;
    s.outputUsed = 0;

    _decompress(s);

    totalOutput += s.outputUsed;

    if (s.outputUsed < 16384) break;
  }

  _close(s);

  final result = createInt8List(totalOutput, 0);
  var offset = 0;

  for (var i = 0; i < chunks.length; i++) {
    final chunk = chunks[i];
    final end = min(totalOutput, offset + 16384);
    final len = end - offset;

    if (len < 16384) {
      result.setAll(offset, chunk.sublist(0, len));
    } else {
      result.setAll(offset, chunk);
    }

    offset += len;
  }

  return result;
}
