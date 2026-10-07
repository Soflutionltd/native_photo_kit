import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_photo_kit/native_photo_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('native_photo_kit');
  final calls = <MethodCall>[];
  Object? reply;

  setUp(() {
    calls.clear();
    reply = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return reply;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('encodeJpeg', () {
    test('sends pixels, size and quality', () async {
      reply = Uint8List.fromList([0xFF, 0xD8]);
      final rgba = Uint8List(2 * 3 * 4);

      final jpeg = await NativePhotoKit.encodeJpeg(
        rgba: rgba,
        width: 2,
        height: 3,
        quality: 80,
      );

      expect(jpeg, [0xFF, 0xD8]);
      expect(calls.single.method, 'encodeJpeg');
      expect(calls.single.arguments, {
        'rgba': rgba,
        'width': 2,
        'height': 3,
        'quality': 80,
      });
    });

    test('rejects a buffer smaller than width * height * 4', () {
      expect(
        () => NativePhotoKit.encodeJpeg(rgba: Uint8List(10), width: 2, height: 3),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });

    test('rejects an out-of-range quality', () {
      expect(
        () => NativePhotoKit.encodeJpeg(
          rgba: Uint8List(4),
          width: 1,
          height: 1,
          quality: 101,
        ),
        throwsRangeError,
      );
    });

    test('fails loudly when the platform returns nothing', () {
      expect(
        () => NativePhotoKit.encodeJpeg(rgba: Uint8List(4), width: 1, height: 1),
        throwsStateError,
      );
    });
  });

  group('orientedSize', () {
    test('maps the platform list to a record', () async {
      reply = [3024, 4032];
      expect(await NativePhotoKit.orientedSize('/photo.jpg'), (width: 3024, height: 4032));
      expect(calls.single.arguments, {'path': '/photo.jpg'});
    });

    test('returns null for an unreadable file', () async {
      expect(await NativePhotoKit.orientedSize('/missing.jpg'), isNull);
    });
  });

  group('coverJpeg and formatForFeed', () {
    test('formatForFeed defaults to Instagram 4:5 at quality 92', () async {
      reply = Uint8List(1);
      await NativePhotoKit.formatForFeed('/photo.jpg');
      expect(calls.single.method, 'formatForFeed');
      expect(calls.single.arguments, {
        'path': '/photo.jpg',
        'width': 1080,
        'height': 1350,
        'quality': 92,
      });
    });

    test('coverJpeg forwards the requested size', () async {
      reply = Uint8List(1);
      await NativePhotoKit.coverJpeg('/photo.jpg', width: 1080, height: 1080, quality: 85);
      expect(calls.single.arguments, {
        'path': '/photo.jpg',
        'width': 1080,
        'height': 1080,
        'quality': 85,
      });
    });

    test('returns null for an unreadable file', () async {
      expect(await NativePhotoKit.formatForFeed('/missing.jpg'), isNull);
      expect(await NativePhotoKit.coverJpeg('/missing.jpg', width: 1, height: 1), isNull);
    });

    test('rejects an empty target size', () {
      expect(() => NativePhotoKit.coverJpeg('/photo.jpg', width: 0, height: 10), throwsRangeError);
      expect(() => NativePhotoKit.formatForFeed('/photo.jpg', height: -1), throwsRangeError);
    });
  });
}
