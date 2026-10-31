import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_compress_next/src/messages.g.dart';
import 'package:video_compress_next/video_compress_next.dart';

import 'fake_host_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late FakeHostApi api;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('vcn_test');
    api = FakeHostApi(cacheDir: temp.path)
      ..files['/in.mp4'] = videoInfo('/in.mp4', frameRate: 60)
      ..outputInfo = (r) => videoInfo(
            r.outputPath,
            width: r.width ?? 1920,
            height: r.height ?? 1080,
            fileSize: 3000000,
            bitrate: r.videoBitrate,
          );
    VideoCompressor.hostApi = api;
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<NativeCompressRequest> started() async {
    await pumpEventQueue();
    return api.requests.single;
  }

  test('compress sends the plan and returns the output info', () async {
    final task = VideoCompressor.compress(
      '/in.mp4',
      options: const CompressOptions(
        trimStart: Duration(seconds: 1),
        trimEnd: Duration(milliseconds: 4500),
        includeAudio: false,
        codec: VideoCodec.hevc,
      ),
    );
    final request = await started();
    expect(request.taskId, task.id);
    expect(request.inputPath, '/in.mp4');
    expect(request.outputPath, startsWith('${temp.path}/VID_'));
    expect(request.outputPath, endsWith('.mp4'));
    expect((request.width, request.height), (1280, 720));
    expect(request.videoBitrate, (0.065 * 1280 * 720 * 30).round());
    expect(request.maxFrameRate, 30);
    expect((request.startMs, request.endMs), (1000, 4500));
    expect(request.includeAudio, isFalse);
    expect(request.codec, NativeVideoCodec.hevc);

    api.complete(task.id);
    final info = await task.result;
    expect(info.path, request.outputPath);
    expect(info.fileSize, 3000000);
    expect((info.width, info.height), (1280, 720));
  });

  test('progress only goes up and closes at the end', () async {
    final task = VideoCompressor.compress('/in.mp4');
    final values = <double>[];
    final done = Completer<void>();
    task.progress.listen(values.add, onDone: done.complete);
    await started();
    await sendProgress(task.id, 0.25);
    await sendProgress(task.id, 0.2);
    await sendProgress(task.id, 0.6);
    await sendProgress('someone-else', 0.9);
    api.complete(task.id);
    await task.result;
    await done.future;
    expect(values, [0.25, 0.6, 1.0]);
  });

  test('cancel stops the native task and fails with cancelled', () async {
    final task = VideoCompressor.compress('/in.mp4');
    await started();
    await task.cancel();
    expect(api.cancelled, [task.id]);
    await expectLater(
      task.result,
      throwsA(isA<VideoCompressException>().having((e) => e.error, 'error', VideoCompressError.cancelled)),
    );
    await task.cancel(); // A second cancel does nothing.
    expect(api.cancelled, [task.id]);
  });

  test('cancel before the native task starts never starts it', () async {
    api.mediaInfoGate = Completer<void>();
    final task = VideoCompressor.compress('/in.mp4');
    await task.cancel();
    api.mediaInfoGate!.complete();
    await expectLater(
      task.result,
      throwsA(isA<VideoCompressException>().having((e) => e.error, 'error', VideoCompressError.cancelled)),
    );
    expect(api.requests, isEmpty);
  });

  test('deleteOrigin deletes the source after success only', () async {
    final source = File('${temp.path}/source.mp4')..writeAsStringSync('video');
    api.files[source.path] = videoInfo(source.path);

    final failing = VideoCompressor.compress(source.path, options: const CompressOptions(deleteOrigin: true));
    await started();
    api.fail(failing.id, 'failed');
    await expectLater(failing.result, throwsA(isA<VideoCompressException>()));
    expect(source.existsSync(), isTrue);

    api.requests.clear();
    final task = VideoCompressor.compress(source.path, options: const CompressOptions(deleteOrigin: true));
    await started();
    api.complete(task.id);
    await task.result;
    expect(source.existsSync(), isFalse);
  });

  test('platform errors become typed exceptions', () async {
    await expectLater(
      VideoCompressor.getMediaInfo('/missing.mp4'),
      throwsA(isA<VideoCompressException>().having((e) => e.error, 'error', VideoCompressError.fileNotFound)),
    );

    final task = VideoCompressor.compress('/in.mp4');
    await started();
    api.fail(task.id, 'unsupported');
    await expectLater(
      task.result,
      throwsA(isA<VideoCompressException>().having((e) => e.error, 'error', VideoCompressError.unsupported)),
    );
  });

  test('thumbnails pass position, quality and size, and can be written to a file', () async {
    final bytes = await VideoCompressor.getThumbnail('/in.mp4',
        position: const Duration(seconds: 2), quality: 70, maxSide: 300);
    expect(bytes.take(3), [0xFF, 0xD8, 0xFF]);
    expect(api.lastThumbnail!.positionMs, 2000);
    expect(api.lastThumbnail!.maxSide, 300);

    await VideoCompressor.getThumbnail('/in.mp4');
    expect(api.lastThumbnail!.positionMs, -1);

    final file = await VideoCompressor.getThumbnailFile('/in.mp4');
    expect(file.path, startsWith('${temp.path}/THUMB_'));
    expect(file.lengthSync(), 4);
  });

  test('deleteAllCache empties the cache folder', () async {
    File('${temp.path}/a.mp4').writeAsStringSync('a');
    Directory('${temp.path}/sub').createSync();
    expect(await VideoCompressor.deleteAllCache(), isTrue);
    expect(temp.listSync(), isEmpty);
  });
}
