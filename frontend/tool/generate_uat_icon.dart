// Generates assets/images/app_icon_uat.png from app_icon.png with a clear UAT badge.
// Run from frontend/: dart run tool/generate_uat_icon.dart

import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const sourcePath = 'assets/images/app_icon.png';
  const outputPath = 'assets/images/app_icon_uat.png';

  final source = File(sourcePath);
  if (!source.existsSync()) {
    stderr.writeln('Missing $sourcePath');
    exit(1);
  }

  final decoded = img.decodeImage(source.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode $sourcePath');
    exit(1);
  }

  final image = img.Image.from(decoded);
  final w = image.width;
  final h = image.height;

  final orange = img.getColor(230, 126, 34);
  final white = img.getColor(255, 255, 255);
  const border = 12;

  // Orange border — visible at small dock sizes.
  img.fillRect(image, 0, 0, w, border, orange);
  img.fillRect(image, 0, h - border, w, h, orange);
  img.fillRect(image, 0, 0, border, h, orange);
  img.fillRect(image, w - border, 0, w, h, orange);

  // Bottom banner with large UAT label.
  final bannerH = (h * 0.26).round();
  final bannerY = h - bannerH;
  img.fillRect(image, 0, bannerY, w, h, orange);

  const label = 'UAT';
  final font = img.arial_48;
  final textH = img.findStringHeight(font, label);
  final textW = _estimateTextWidth(font, label);
  img.drawString(
    image,
    font,
    (w - textW) ~/ 2,
    bannerY + ((bannerH - textH) ~/ 2),
    label,
    color: white,
  );

  // Top-right ribbon for small icon legibility.
  final ribbon = (w * 0.36).round();
  img.fillRect(image, w - ribbon, 0, w, ribbon, orange);
  const ribbonLabel = 'UAT';
  final smallFont = img.arial_24;
  final rw = _estimateTextWidth(smallFont, ribbonLabel);
  final rh = img.findStringHeight(smallFont, ribbonLabel);
  img.drawString(
    image,
    smallFont,
    w - ribbon + ((ribbon - rw) ~/ 2),
    (ribbon - rh) ~/ 2,
    ribbonLabel,
    color: white,
  );

  File(outputPath).writeAsBytesSync(img.encodePng(image));
  stdout.writeln('Wrote $outputPath (${w}x$h)');
}

int _estimateTextWidth(img.BitmapFont font, String text) {
  var width = 0;
  for (final code in text.codeUnits) {
    if (font.characters.containsKey(code)) {
      width += font.characters[code]!.xadvance;
    } else {
      width += font.size ~/ 2;
    }
  }
  return width;
}
