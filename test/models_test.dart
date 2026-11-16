import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_compress_next/src/messages.g.dart';
import 'package:video_compress_next/video_compress.dart';
import 'package:video_compress_next/video_compress_next.dart';

void main() {
  group('ObservableBuilder', () {
    test('progress sent while nobody listens is not replayed later', () async {
      final builder = ObservableBuilder<double>();
      builder.next(5);
      builder.subscribe((_) {}).unsubscribe();
      builder
        ..next(10)
        ..next(20);

      final got = <double>[];
      builder.subscribe(got.add);
      builder.next(30);
      await pumpEventQueue();
      expect(got, [30]);
    });

    test('unsubscribe ends the listener and allows a new one', () async {
      final builder = ObservableBuilder<int>();
      var done = false;
      final first = <int>[];
      final subscription =
          builder.subscribe(first.add, onDone: () => done = true);
      builder.next(1);
      await pumpEventQueue();
      subscription.unsubscribe();
      await pumpEventQueue();
      expect(done, isTrue);

      final second = <int>[];
      builder.subscribe(second.add);
      builder.next(2);
      await pumpEventQueue();
      expect(first, [1]);
      expect(second, [2]);
      expect(builder.notSubscribed, isFalse);
    });
  });

  group('VideoCompressException.fromPlatform', () {
    test('known codes map to their error and keep the message', () {
      for (final (code, error) in [
        ('file_not_found', VideoCompressError.fileNotFound),
        ('unsupported', VideoCompressError.unsupported),
        ('cancelled', VideoCompressError.cancelled),
        ('failed', VideoCompressError.failed),
      ]) {
        final e = VideoCompressException.fromPlatform(
            PlatformException(code: code, message: 'why'));
        expect(e.error, error, reason: code);
        expect(e.message, 'why', reason: code);
      }
    });

    test('an unknown code becomes failed and stays in the message', () {
      final e = VideoCompressException.fromPlatform(PlatformException(
          code: 'channel-error', message: 'gone', details: 'engine'));
      expect(e.error, VideoCompressError.failed);
      expect(e.message, 'channel-error: gone (engine)');
      expect(e.toString(),
          'VideoCompressException(failed: channel-error: gone (engine))');
    });
  });

  group('CompressOptions', () {
    test('defaults are 720p H.264 at 30 fps with sound', () {
      const o = CompressOptions();
      expect(o.maxShortSide, 720);
      expect(o.maxLongSide, isNull);
      expect(o.maxFrameRate, 30);
      expect(o.includeAudio, isTrue);
      expect(o.codec, VideoCodec.h264);
      expect(o.deleteOrigin, isFalse);
    });

    test('copyWith keeps what is not passed and sets what is', () {
      const o = CompressOptions(trimStart: Duration(seconds: 1));
      final c = o.copyWith(
          codec: VideoCodec.hevc,
          trimEnd: const Duration(seconds: 4),
          outputPath: '/out.mp4');
      expect(c.trimStart, const Duration(seconds: 1));
      expect(c.trimEnd, const Duration(seconds: 4));
      expect(c.codec, VideoCodec.hevc);
      expect(c.outputPath, '/out.mp4');
      expect(c.maxShortSide, 720);
      expect(c.copyWith(trimStart: null).trimStart, isNull);
    });

    test('non-positive limits are rejected', () {
      expect(() => CompressOptions(maxShortSide: 0), throwsAssertionError);
      expect(() => CompressOptions(videoBitrate: -1), throwsAssertionError);
    });
  });

  test('VideoInfo and MediaInfo carry every field from the platform', () {
    final info = VideoInfo.fromNative(NativeMediaInfo(
      path: '/v.mp4',
      width: 1080,
      height: 1920,
      rotation: 90,
      durationMs: 2500,
      fileSize: 999,
      hasAudio: false,
      bitrate: 4000000,
      frameRate: 29.97,
      videoMimeType: 'video/hevc',
      title: 'T',
    ));
    expect(info.duration, const Duration(milliseconds: 2500));
    expect(info.frameRate, 29.97);
    expect(info.toString(), contains('1080x1920'));

    final media = MediaInfo.fromVideoInfo(info, isCancel: false);
    expect(media.orientation, 90);
    expect(media.duration, 2500.0);
    expect(media.title, 'T');
    expect(media.author, '');
    expect(media.file!.path, '/v.mp4');
    expect(media.toJson()['isCancel'], isFalse);
  });

  test('every VideoQuality caps the shorter side', () {
    for (final q in VideoQuality.values) {
      expect(q.options.maxShortSide, isNotNull, reason: q.name);
    }
    expect(VideoQuality.Res1920x1080Quality.options.maxLongSide, 1920);
  });
}
