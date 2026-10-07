## 0.1.0

- `encodeJpeg`: raw RGBA (for example `ui.Image.toByteData`) to sRGB JPEG.
- `orientedSize`: displayed size of an image file, EXIF orientation applied, header only.
- `coverJpeg`: center crop that fills an exact size, decoded straight at that size.
- `formatForFeed`: whole photo over a blurred, darkened copy of itself (Instagram 4:5 by default).
- iOS (ImageIO + Core Image, Swift Package Manager and CocoaPods) and Android (BitmapFactory + `Bitmap.compress`).
