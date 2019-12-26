import 'dart:io';

import 'package:brotli/brotli.dart';
import 'package:test/test.dart';

void main() {
  test('Base Dictionary Words', () {
    final input = [
      0x1b,
      0x03,
      0x00,
      0x00,
      0x00,
      0x00,
      0x80,
      0xe3,
      0xb4,
      0x0d,
      0x00,
      0x00,
      0x07,
      0x5b,
      0x26,
      0x31,
      0x40,
      0x02,
      0x00,
      0xe0,
      0x4e,
      0x1b,
      0x41,
      0x02,
    ];

    final output = brotli.decodeToString(input);
    expect(output, 'time');
  });

  test('Metadata', () {
    final input = [1, 11, 0, 42, 3];
    final output = brotli.decodeToString(input);
    expect(output, '');
  });

  test('Empty', () {
    var input = [6];
    var output = brotli.decodeToString(input);
    expect(output, '');

    input = [0x81, 1];
    output = brotli.decodeToString(input);
    expect(output, '');
  });

  test('Block Count Message', () {
    final input = [
      0x1b,
      0x0b,
      0x00,
      0x11,
      0x01,
      0x8c,
      0xc1,
      0xc5,
      0x0d,
      0x08,
      0x00,
      0x22,
      0x65,
      0xe1,
      0xfc,
      0xfd,
      0x22,
      0x2c,
      0xc4,
      0x00,
      0x00,
      0x38,
      0xd8,
      0x32,
      0x89,
      0x01,
      0x12,
      0x00,
      0x00,
      0x77,
      0xda,
      0x04,
      0x10,
      0x42,
      0x00,
      0x00,
      0x00,
    ];

    final output = brotli.decodeToString(input);
    expect(output, 'aabbaaaaabab');
  });

  test('Intact Distance RingBuffer', () {
    final input = [
      0x1b,
      0x0a,
      0x00,
      0x00,
      0x00,
      0x00,
      0x80,
      0xe3,
      0xb4,
      0x0d,
      0x00,
      0x00,
      0x07,
      0x5b,
      0x26,
      0x31,
      0x40,
      0x02,
      0x00,
      0xe0,
      0x4e,
      0x1b,
      0xa1,
      0x80,
      0x20,
      0x00,
    ];

    final output = brotli.decodeToString(input);
    expect(output, 'himselfself');
  });

  test('Compressed Uncompressed Short Compressed Small Window', () {
    final input = [
      0x21,
      0xf4,
      0x0f,
      0x00,
      0x00,
      0x00,
      0x00,
      0x1c,
      0xa7,
      0x6d,
      0x00,
      0x00,
      0x38,
      0xd8,
      0x32,
      0x89,
      0x01,
      0x12,
      0x00,
      0x00,
      0x77,
      0xda,
      0x34,
      0x7b,
      0xdb,
      0x50,
      0x80,
      0x02,
      0x80,
      0x62,
      0x62,
      0x62,
      0x62,
      0x62,
      0x62,
      0x31,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x38,
      0x4e,
      0xdb,
      0x00,
      0x00,
      0x70,
      0xb0,
      0x65,
      0x12,
      0x03,
      0x24,
      0x00,
      0x00,
      0xee,
      0xb4,
      0x11,
      0x24,
      0x00,
    ];

    final output = brotli.decodeToString(input);
    expect(
      output,
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      'aaaaaaaaaaaaaabbbbbbbbbb',
    );
  });

  test('Lorem Ipsum', () {
    final output = brotli.decodeToString(
      File('./brotli.br').readAsBytesSync(),
    );

    const loremIpsum =
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.';

    expect(output, loremIpsum);
  });
}
