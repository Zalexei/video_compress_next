# video_compress_next example

The app in [lib/main.dart](lib/main.dart) opens a bundled sample (1080p at
60 fps, or a rotated portrait video) or a video from the gallery, shows its
info and a thumbnail, and compresses it at the chosen size, with or without
sound, in H.264 or HEVC. It shows the progress, can cancel, and compares the
result with the source.

```bash
flutter run
```

## Compress a video

```dart
import 'package:video_compress_next/video_compress_next.dart';

Future<void> compress(String path) async {
  final task = VideoCompressor.compress(
    path,
    options: const CompressOptions(maxShortSide: 720, codec: VideoCodec.h264),
  );
  task.progress.listen((p) => print('${(p * 100).round()} %'));
  // task.cancel() stops it; task.result then fails with
  // VideoCompressError.cancelled.

  try {
    final result = await task.result;
    print('${result.path}: ${result.width}x${result.height}, '
        '${result.fileSize} bytes');
  } on VideoCompressException catch (e) {
    print('Failed: ${e.error}, ${e.message}');
  }
}
```

## Info and thumbnails

```dart
final info = await VideoCompressor.getMediaInfo(path);
print('${info.width}x${info.height}, ${info.duration}, ${info.frameRate} fps');

final jpeg = await VideoCompressor.getThumbnail(
  path,
  position: const Duration(seconds: 1),
  maxSide: 512,
);
```

## Code written for video_compress

The same calls work after changing the import:

```dart
import 'package:video_compress_next/video_compress.dart';

final subscription = VideoCompress.compressProgress$.subscribe((percent) {
  print('$percent %');
});
final MediaInfo? info = await VideoCompress.compressVideo(
  path,
  quality: VideoQuality.DefaultQuality,
  includeAudio: true,
);
subscription.unsubscribe();
```

## Tests

`integration_test/plugin_integration_test.dart` compresses the bundled
samples on a device, emulator or simulator:

```bash
flutter test integration_test -d <device>
```
