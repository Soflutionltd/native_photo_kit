/// Fast native photo pipeline for Flutter.
///
/// Decoding, resizing, compositing and JPEG encoding run on the platform's
/// own image stack: ImageIO and Core Image (GPU) on iOS, `BitmapFactory`,
/// `Canvas` and `Bitmap.compress` (libjpeg-turbo) on Android.
library;

import 'package:flutter/services.dart';

/// Size of a photo as displayed, with its EXIF orientation applied.
typedef PhotoSize = ({int width, int height});

/// Entry point of the plugin. Every method runs off the UI thread.
abstract final class NativePhotoKit {
  static const MethodChannel _channel = MethodChannel('native_photo_kit');

  /// Encodes 8-bit RGBA pixels, such as the output of
  /// `ui.Image.toByteData(format: ui.ImageByteFormat.rawRgba)`, to an sRGB JPEG.
  ///
  /// [quality] goes from 0 to 100. Alpha is ignored: JPEG has no transparency.
  static Future<Uint8List> encodeJpeg({
    required Uint8List rgba,
    required int width,
    required int height,
    int quality = 92,
  }) async {
    _checkSize(width, height);
    _checkQuality(quality);
    if (rgba.length < width * height * 4) {
      throw ArgumentError.value(
        rgba.length,
        'rgba',
        'needs at least width * height * 4 = ${width * height * 4} bytes',
      );
    }
    final bytes = await _channel.invokeMethod<Uint8List>('encodeJpeg', {
      'rgba': rgba,
      'width': width,
      'height': height,
      'quality': quality,
    });
    if (bytes == null) {
      throw StateError('Native JPEG encoder returned no data');
    }
    return bytes;
  }

  /// Width and height of the image file at [path] as it is displayed, with
  /// the EXIF orientation applied. Only the header is read.
  ///
  /// Returns null when the file is missing or is not a readable image.
  static Future<PhotoSize?> orientedSize(String path) async {
    final size = await _channel.invokeMethod<List<Object?>>('orientedSize', {
      'path': path,
    });
    if (size == null) return null;
    return (width: size[0]! as int, height: size[1]! as int);
  }

  /// Scales the photo at [path] to fill exactly [width]×[height], crops the
  /// overflow around the center and encodes the result to JPEG.
  ///
  /// The file is decoded directly at the needed size, never at full
  /// resolution. Returns null when the file is not a readable image.
  static Future<Uint8List?> coverJpeg(
    String path, {
    required int width,
    required int height,
    int quality = 92,
  }) {
    _checkSize(width, height);
    _checkQuality(quality);
    return _channel.invokeMethod<Uint8List>('coverJpeg', {
      'path': path,
      'width': width,
      'height': height,
      'quality': quality,
    });
  }

  /// Fits the whole photo at [path] inside [width]×[height], centered over a
  /// blurred and darkened copy of itself, and encodes the result to JPEG.
  ///
  /// This is the classic way to post any photo in a fixed feed format, such
  /// as Instagram's 4:5 (1080×1350), without cropping it. Returns null when
  /// the file is not a readable image.
  static Future<Uint8List?> formatForFeed(
    String path, {
    int width = 1080,
    int height = 1350,
    int quality = 92,
  }) {
    _checkSize(width, height);
    _checkQuality(quality);
    return _channel.invokeMethod<Uint8List>('formatForFeed', {
      'path': path,
      'width': width,
      'height': height,
      'quality': quality,
    });
  }

  static void _checkSize(int width, int height) {
    if (width <= 0) throw RangeError.range(width, 1, null, 'width');
    if (height <= 0) throw RangeError.range(height, 1, null, 'height');
  }

  static void _checkQuality(int quality) {
    RangeError.checkValueInInterval(quality, 0, 100, 'quality');
  }
}
