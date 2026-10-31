// Runs on a device or emulator: flutter test integration_test -d <device>
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:video_compress_next/video_compress.dart' as compat;
import 'package:video_compress_next/video_compress_next.dart';

Future<String> sample(String name, {String prefix = 'it'}) async {
  final file = File('${await VideoCompressor.cacheDirectory()}/${prefix}_$name');
  final data = await rootBundle.load('assets/$name');
  await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  return file.path;
}

Future<(int, int)> jpegSize(Uint8List bytes) async {
  expect(bytes.take(2), [0xFF, 0xD8], reason: 'JPEG header');
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  return (image.width, image.height);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String landscape;
  late String portrait;

  setUpAll(() async {
    await VideoCompressor.deleteAllCache();
    landscape = await sample('landscape.mp4');
    portrait = await sample('portrait.mp4');
  });

  testWidgets('reads media info', (_) async {
    final info = await VideoCompressor.getMediaInfo(landscape);
    expect((info.width, info.height, info.rotation), (1920, 1080, 0));
    expect(info.duration.inMilliseconds, closeTo(3000, 100));
    expect(info.frameRate, closeTo(60, 1));
    expect(info.hasAudio, isTrue);
    expect(info.videoMimeType, 'video/avc');
    expect(info.title, 'Landscape sample');

    final rotated = await VideoCompressor.getMediaInfo(portrait);
    expect(rotated.rotation % 180, 90);
    expect((rotated.width, rotated.height), (720, 1280), reason: 'displayed size, after rotation');
  });

  testWidgets('compresses 1080p60 to a smaller, readable 720p30 file', (_) async {
    final source = await VideoCompressor.getMediaInfo(landscape);
    final watch = Stopwatch()..start();
    final task = VideoCompressor.compress(landscape);
    final progress = <double>[];
    task.progress.listen(progress.add);
    final result = await task.result;
    debugPrint('MEASURE ${source.fileSize} -> ${result.fileSize} bytes, '
        '${result.width}x${result.height}, ${result.frameRate?.toStringAsFixed(1)} fps, '
        '${result.bitrate} bps, ${watch.elapsedMilliseconds} ms, ${progress.length} progress events');

    expect(File(result.path).existsSync(), isTrue);
    expect(result.fileSize, lessThan(source.fileSize ~/ 2));
    expect((result.width, result.height), (1280, 720));
    expect(result.frameRate, lessThan(31));
    expect(result.duration.inMilliseconds, closeTo(3000, 200));
    expect(result.hasAudio, isTrue);
    expect(result.videoMimeType, 'video/avc');
    expect(progress.last, 1.0);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThan(progress[i - 1]));
    }
    // The output decodes: a frame from the middle comes back as a 1280x720 JPEG.
    final frame = await VideoCompressor.getThumbnail(result.path, position: const Duration(milliseconds: 1500));
    expect(await jpegSize(frame), (1280, 720));
  });

  testWidgets('keeps a rotated portrait video portrait', (_) async {
    final result = await VideoCompressor.compress(portrait, options: const CompressOptions(maxShortSide: 480)).result;
    expect((result.width, result.height), (480, 854));
    final frame = await VideoCompressor.getThumbnail(result.path);
    final (w, h) = await jpegSize(frame);
    expect(w, lessThan(h));
  });

  testWidgets('trims and drops audio', (_) async {
    final result = await VideoCompressor.compress(
      landscape,
      options: const CompressOptions(
        maxShortSide: 360,
        includeAudio: false,
        trimStart: Duration(milliseconds: 500),
        trimEnd: Duration(seconds: 2),
      ),
    ).result;
    expect((result.width, result.height), (640, 360));
    expect(result.hasAudio, isFalse);
    expect(result.duration.inMilliseconds, closeTo(1500, 150));
  });

  testWidgets('HEVC, or the closest codec the device has', (_) async {
    final source = await VideoCompressor.getMediaInfo(landscape);
    final result = await VideoCompressor.compress(
      landscape,
      options: const CompressOptions(codec: VideoCodec.hevc, maxShortSide: 480),
    ).result;
    expect(result.videoMimeType, anyOf('video/hevc', 'video/avc'));
    expect(result.fileSize, lessThan(source.fileSize));
  });

  testWidgets('cancel stops the work and removes the partial file', (_) async {
    final out = '${await VideoCompressor.cacheDirectory()}/cancelled.mp4';
    final task = VideoCompressor.compress(
      landscape,
      options: CompressOptions(maxShortSide: null, maxFrameRate: null, outputPath: out),
    );
    final cancelled = expectLater(
      task.result,
      throwsA(isA<VideoCompressException>().having((e) => e.error, 'error', VideoCompressError.cancelled)),
    );
    await task.progress.firstWhere((p) => p > 0.05);
    await task.cancel();
    await cancelled;
    expect(File(out).existsSync(), isFalse);
  });

  testWidgets('a missing file fails with fileNotFound', (_) async {
    await expectLater(
      VideoCompressor.compress('/no/such/video.mp4').result,
      throwsA(isA<VideoCompressException>().having((e) => e.error, 'error', VideoCompressError.fileNotFound)),
    );
  });

  testWidgets('video_compress API works the same way', (_) async {
    final copy = await sample('landscape.mp4', prefix: 'compat');
    final progress = <double>[];
    final subscription = compat.VideoCompress.compressProgress$.subscribe(progress.add);
    final info = await compat.VideoCompress.compressVideo(
      copy,
      quality: compat.VideoQuality.LowQuality,
      deleteOrigin: true,
    );
    subscription.unsubscribe();

    expect(info, isNotNull);
    expect((info!.width, info.height), (640, 360));
    expect(info.isCancel, isFalse);
    expect(info.file!.existsSync(), isTrue);
    expect(info.duration, closeTo(3000, 200));
    expect(File(copy).existsSync(), isFalse, reason: 'deleteOrigin');
    expect(progress, isNotEmpty);
    expect(progress.last, 100.0);

    final thumb = await compat.VideoCompress.getFileThumbnail(info.path!, quality: 80);
    expect(thumb.existsSync(), isTrue);
    expect(await jpegSize(thumb.readAsBytesSync()), (512, 288));

    final media = await compat.VideoCompress.getMediaInfo(landscape);
    expect((media.width, media.height, media.filesize), (1920, 1080, File(landscape).lengthSync()));
    expect(await compat.VideoCompress.deleteAllCache(), isTrue);
  });
}
