import 'package:brotli/src/decoder/input_stream.dart';
import 'package:brotli/src/helper.dart';

class State {
  var ringBuffer = createInt8List(0);
  var contextModes = createInt8List(0);
  var contextMap = createInt8List(0);
  var distContextMap = createInt8List(0);
  var distExtraBits = createInt8List(0);
  var output = createInt8List(0);
  var byteBuffer = createInt8List(0);
  var shortBuffer = createInt16List(0);
  var intBuffer = createInt32List(0);
  var rings = createInt32List(10);
  var blockTrees = createInt32List(0);
  var literalTreeGroup = createInt32List(0);
  var commandTreeGroup = createInt32List(0);
  var distanceTreeGroup = createInt32List(0);
  var distOffset = createInt32List(0);

  int accumulator = 0;

  int runningState = 0;
  int nextRunningState = 0;
  int bitOffset = 0;
  int halfOffset = 0;
  int tailBytes = 0;
  int endOfStreamReached = 0;
  int metaBlockLength = 0;
  int inputEnd = 0;
  int isUncompressed = 0;
  int isMetadata = 0;
  int literalBlockLength = 0;
  int numLiteralBlockTypes = 0;
  int commandBlockLength = 0;
  int numCommandBlockTypes = 0;
  int distanceBlockLength = 0;
  int numDistanceBlockTypes = 0;
  int pos = 0;
  int maxDistance = 0;
  int distRbIdx = 0;
  int trivialLiteralContext = 0;
  int literalTreeIdx = 0;
  int commandTreeIdx = 0;
  int j = 0;
  int insertLength = 0;
  int contextMapSlice = 0;
  int distContextMapSlice = 0;
  int contextLookupOffset1 = 0;
  int contextLookupOffset2 = 0;
  int distanceCode = 0;
  int numDirectDistanceCodes = 0;
  int distancePostfixMask = 0;
  int distancePostfixBits = 0;
  int distance = 0;
  int copyLength = 0;
  int maxBackwardDistance = 0;
  int maxRingBufferSize = 0;
  int ringBufferSize = 0;
  int expectedTotalSize = 0;
  int outputOffset = 0;
  int outputLength = 0;
  int outputUsed = 0;
  int ringBufferBytesWritten = 0;
  int ringBufferBytesReady = 0;
  int isEager = 0;
  int isLargeWindow = 0;

  InputStream input;

  State() {
    rings[0] = 16;
    rings[1] = 15;
    rings[2] = 11;
    rings[3] = 4;
  }
}
