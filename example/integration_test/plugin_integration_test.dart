import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:native_photo_kit/native_photo_kit.dart';

/// Displayed upright, the portrait asset is 900×1200: red on top, blue at the
/// bottom. Its pixels are stored on their side with EXIF orientation 6, so any
/// method that ignores EXIF puts the colors in the wrong place.
Future<String> _assetFile(String name) async {
  final data = await rootBundle.load('assets/$name');
  final file = File('${Directory.systemTemp.path}/native_photo_kit_$name');
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<ui.Image> _decode(Uint8List jpeg) async {
  final codec = await ui.instantiateImageCodec(jpeg);
  return (await codec.getNextFrame()).image;
}

Future<List<int>> _pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final offset = (y * image.width + x) * 4;
  return [data.getUint8(offset), data.getUint8(offset + 1), data.getUint8(offset + 2)];
}

Matcher _closeToColor(List<int> expected) => predicate<List<int>>(
      (actual) => List.generate(3, (i) => (actual[i] - expected[i]).abs()).every((d) => d <= 24),
      'within 24 of $expected',
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String portrait;
  late String landscape;

  setUpAll(() async {
    portrait = await _assetFile('portrait_exif6.jpg');
    landscape = await _assetFile('landscape.jpg');
  });

  testWidgets('orientedSize applies EXIF orientation', (tester) async {
    expect(await NativePhotoKit.orientedSize(portrait), (width: 900, height: 1200));
    expect(await NativePhotoKit.orientedSize(landscape), (width: 1600, height: 1200));
  });

  testWidgets('coverJpeg fills the exact size, upright', (tester) async {
    final jpeg = await NativePhotoKit.coverJpeg(portrait, width: 600, height: 600);
    final image = await _decode(jpeg!);

    expect((image.width, image.height), (600, 600));
    expect(await _pixel(image, 300, 30), _closeToColor([224, 32, 32]));
    expect(await _pixel(image, 300, 570), _closeToColor([32, 64, 224]));
  });

  testWidgets('formatForFeed centers the whole photo over a blurred copy', (tester) async {
    final jpeg = await NativePhotoKit.formatForFeed(landscape);
    final image = await _decode(jpeg!);

    expect((image.width, image.height), (1080, 1350));

    // 1600×1200 fits as 1080×810: the photo spans y 270 to 1080, the
    // blurred background shows above it, darkened by a 60/255 black veil.
    final photoTop = await _pixel(image, 540, 290);
    final background = await _pixel(image, 540, 100);
    int brightness(List<int> c) => c[0] + c[1] + c[2];
    final ratio = brightness(background) / brightness(photoTop);
    expect(ratio, inInclusiveRange(0.65, 0.9));
  });

  testWidgets('encodeJpeg round-trips raw RGBA from a ui.Image', (tester) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..drawRect(const ui.Rect.fromLTWH(0, 0, 400, 150), ui.Paint()..color = const ui.Color(0xFF20C060))
      ..drawRect(const ui.Rect.fromLTWH(0, 150, 400, 150), ui.Paint()..color = const ui.Color(0xFFF0B020));
    final source = await recorder.endRecording().toImage(400, 300);
    final rgba = (await source.toByteData(format: ui.ImageByteFormat.rawRgba))!;

    final jpeg = await NativePhotoKit.encodeJpeg(
      rgba: rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      width: source.width,
      height: source.height,
    );
    final image = await _decode(jpeg);

    expect(jpeg.sublist(0, 2), [0xFF, 0xD8]);
    expect((image.width, image.height), (400, 300));
    expect(await _pixel(image, 200, 60), _closeToColor([32, 192, 96]));
    expect(await _pixel(image, 200, 240), _closeToColor([240, 176, 32]));
  });

  testWidgets('unreadable files return null', (tester) async {
    final missing = '${Directory.systemTemp.path}/native_photo_kit_missing.jpg';
    final notAnImage = File('${Directory.systemTemp.path}/native_photo_kit_text.jpg')
      ..writeAsStringSync('not a photo');

    expect(await NativePhotoKit.orientedSize(missing), isNull);
    expect(await NativePhotoKit.coverJpeg(missing, width: 10, height: 10), isNull);
    expect(await NativePhotoKit.formatForFeed(notAnImage.path), isNull);
  });
}
