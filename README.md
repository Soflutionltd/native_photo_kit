# native_photo_kit

Native photo pipeline for Flutter. It does the heavy image work on each platform's own image stack and not in Dart:

- **iOS**: ImageIO and Core Image (Metal)
- **Android**: `BitmapFactory`, `Canvas` and `Bitmap.compress` (libjpeg-turbo)

Flutter's `dart:ui` can decode images but can only encode PNG. Pure-Dart encoders and resizers such as `package:image` are portable but slow on 12 MP phone photos, even in an isolate. This plugin hands those steps to code that runs in a few dozen milliseconds.

| Method | What it does |
|---|---|
| `encodeJpeg` | Raw RGBA (for example from `ui.Image.toByteData`) to an sRGB JPEG |
| `orientedSize` | Displayed size of an image file with EXIF orientation applied; reads only the header |
| `coverJpeg` | Center crop that fills an exact size, decoded straight at that size |
| `formatForFeed` | The whole photo centered over a blurred, darkened copy of itself (Instagram 4:5 by default) |

Every method runs off the UI thread. File inputs accept any format the platform reads: JPEG, PNG and HEIC/HEIF on both platforms (HEIC needs Android 9 or later), plus WebP and others.

## Benchmarks

JPEG encoding of raw RGBA at quality 92. Measured on the iOS Simulator on an Apple Silicon Mac, against `package:image` running in an isolate:

| Image | `native_photo_kit` | `package:image` |
|---|---:|---:|
| 1620 × 2160 | 29 ms | 412 ms |
| 3024 × 4032 (12 MP) | 96 ms | 1270 ms |

On the same setup, `formatForFeed` on a 12 MP photo, decoding included, takes 160 to 300 ms. The first call takes about 600 ms while Core Image warms up. Real devices give different absolute numbers, so measure on your target hardware.

## Usage

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:native_photo_kit/native_photo_kit.dart';

// Encode a rendered ui.Image (for example the output of a shader) to JPEG.
Future<Uint8List> toJpeg(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return NativePhotoKit.encodeJpeg(
    rgba: data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    width: image.width,
    height: image.height,
    quality: 92,
  );
}

// Displayed size of a camera photo, EXIF rotation included.
final size = await NativePhotoKit.orientedSize(path); // (width: 3024, height: 4032)

// Square thumbnail, decoded at 600 × 600 and not at full resolution.
final thumbnail = await NativePhotoKit.coverJpeg(path, width: 600, height: 600);

// Any photo as a 1080 × 1350 Instagram post, without cropping it.
final post = await NativePhotoKit.formatForFeed(path);
```

The file methods return `null` when the file is missing or is not a readable image. `encodeJpeg` throws an `ArgumentError` when the buffer is shorter than `width * height * 4`, and a `RangeError` for a size below 1 or a quality outside 0 to 100.

## Output

- JPEGs are sRGB. Alpha is dropped, because JPEG has no transparency.
- EXIF orientation is applied to the pixels, so the output is upright and carries no orientation tag.
- Resizing uses Lanczos on iOS and bilinear filtering after power-of-two subsampling on Android.
- On iOS, the `formatForFeed` background is a Gaussian blur (sigma 12). On Android it is an equivalent box blur. Both are darkened by a 60/255 black veil.

## Platforms

| Platform | Minimum | Notes |
|---|---|---|
| iOS | 15.0 | Swift Package Manager and CocoaPods |
| Android | API 24 | |

Web and desktop are not supported.

## License

MIT. See [LICENSE](LICENSE).
