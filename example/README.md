# native_photo_kit example

Demo app and integration tests for `native_photo_kit`.

- `lib/main.dart`: formats the bundled photos with `coverJpeg` and `formatForFeed`, and shows the time each call takes.
- `integration_test/`: checks EXIF orientation, exact output sizes and pixel content on a real device or simulator.

```sh
flutter run
flutter test integration_test
```
