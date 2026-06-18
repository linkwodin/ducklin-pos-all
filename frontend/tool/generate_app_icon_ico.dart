// Generates windows/runner/resources/app_icon.ico from a PNG (Vista+ PNG-in-ICO).
// Run from frontend/:
//   dart run tool/generate_app_icon_ico.dart
//   dart run tool/generate_app_icon_ico.dart assets/images/app_icon_uat.png

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final pngPath = args.isNotEmpty ? args[0] : 'assets/images/app_icon.png';
  final icoPath = args.length > 1
      ? args[1]
      : 'windows/runner/resources/app_icon.ico';

  final source = File(pngPath);
  if (!source.existsSync()) {
    stderr.writeln('Missing PNG: $pngPath');
    exit(1);
  }

  final decoded = img.decodeImage(source.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode PNG: $pngPath');
    exit(1);
  }

  const sizes = [256, 48, 32, 16];
  final entries = <_IcoEntry>[];
  for (final size in sizes) {
    final resized = img.copyResize(
      decoded,
      width: size,
      height: size,
      interpolation: img.Interpolation.cubic,
    );
    entries.add(_IcoEntry(
      size,
      size,
      Uint8List.fromList(img.encodePng(resized)),
    ));
  }

  final outFile = File(icoPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(_buildIco(entries));
  stdout.writeln('Wrote $icoPath (${outFile.lengthSync()} bytes)');
}

class _IcoEntry {
  _IcoEntry(this.width, this.height, this.data);

  final int width;
  final int height;
  final Uint8List data;
}

Uint8List _buildIco(List<_IcoEntry> entries) {
  final headerSize = 6 + 16 * entries.length;
  var offset = headerSize;
  final totalSize =
      headerSize + entries.fold<int>(0, (sum, e) => sum + e.data.length);
  final bytes = Uint8List(totalSize);
  final bd = ByteData.sublistView(bytes);

  bd.setUint16(0, 0, Endian.little);
  bd.setUint16(2, 1, Endian.little);
  bd.setUint16(4, entries.length, Endian.little);

  var dirOffset = 6;
  for (final entry in entries) {
    bd.setUint8(dirOffset, entry.width >= 256 ? 0 : entry.width);
    bd.setUint8(dirOffset + 1, entry.height >= 256 ? 0 : entry.height);
    bd.setUint8(dirOffset + 2, 0);
    bd.setUint8(dirOffset + 3, 0);
    bd.setUint16(dirOffset + 4, 1, Endian.little);
    bd.setUint16(dirOffset + 6, 32, Endian.little);
    bd.setUint32(dirOffset + 8, entry.data.length, Endian.little);
    bd.setUint32(dirOffset + 12, offset, Endian.little);
    dirOffset += 16;
    bytes.setRange(offset, offset + entry.data.length, entry.data);
    offset += entry.data.length;
  }

  return bytes;
}
