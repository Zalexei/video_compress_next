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

    expect(request.outputPath, endsWith('.part.mp4'));
    api.complete(task.id);
    final info = await task.result;
    final finalPath = request.outputPath.replaceAll('.part.mp4', '');
    expect(info.path, finalPath);
    expect(File(finalPath).existsSync(), isTrue);
    expect(File(request.outputPath).existsSync(), isFalse, reason: 'the part file is renamed');
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

  test('an output path that is the input is refused before anything is touched', () async {
    final source = File('${temp.path}/same.mp4')..writeAsStringSync('video');
    api.files[source.path] = videoInfo(source.path);
    for (final output in [source.path, 'file://${source.path}', '${temp.path}/./same.mp4']) {
      final task = VideoCompressor.compress(source.path, options: CompressOptions(outputPath: output));
      await expectLater(
        task.result,
        throwsA(isA<VideoCompressException>().having((e) => e.error, 'error', VideoCompressError.failed)),
      );
    }
    expect(api.requests, isEmpty);
    expect(source.readAsStringSync(), 'video');
  });

  test('a cancel that comes after the platform finished still cancels and keeps the source', () async {
    final source = File('${temp.path}/keep.mp4')..writeAsStringSync('video');
    api
      ..files[source.path] = videoInfo(source.path)
      ..cancelStopsTask = false;
    final task = VideoCompressor.compress(source.path, options: const CompressOptions(deleteOrigin: true));
    final request = await started();
    final cancelled = expectLater(
      task.result,
      throwsA(isA<VideoCompressException>().having((e) => e.error, 'error', VideoCompressError.cancelled)),
    );
    await task.cancel();
    api.complete(task.id);
    await cancelled;
    expect(source.existsSync(), isTrue);
    expect(File(request.outputPath).existsSync(), isFalse);
    expect(File(request.outputPath.replaceAll('.part.mp4', '')).existsSync(), isFalse);
  });

  test('a failed compression leaves an existing output file alone', () async {
    final output = File('${temp.path}/out.mp4')..writeAsStringSync('previous result');
    final task = VideoCompressor.compress('/in.mp4', options: CompressOptions(outputPath: output.path));
    await started();
    api.fail(task.id, 'failed');
    await expectLater(task.result, throwsA(isA<VideoCompressException>()));
    expect(output.readAsStringSync(), 'previous result');
  });

  test('an unreadable or short result fails, is removed and keeps the source', () async {
    final source = File('${temp.path}/src.mp4')..writeAsStringSync('video');
    api.files[source.path] = videoInfo(source.path, durationMs: 10000);

    api.outputInfo = (r) => videoInfo(r.outputPath, durationMs: 4000);
    var task = VideoCompressor.compress(source.path, options: const CompressOptions(deleteOrigin: true));
    var request = await started();
    api.complete(task.id);
    await expectLater(
      task.result,
      throwsA(isA<VideoCompressException>().having((e) => e.message, 'message', contains('long instead of'))),
    );
    expect(File(request.outputPath).existsSync(), isFalse);
    expect(source.existsSync(), isTrue);

    // A trimmed result is measured against the trim, not the whole video.
    api.requests.clear();
    task = VideoCompressor.compress(source.path,
        options: const CompressOptions(trimStart: Duration(seconds: 2), trimEnd: Duration(seconds: 6)));
    await started();
    api.complete(task.id);
    expect((await task.result).duration, const Duration(seconds: 4));

    api.requests.clear();
    task = VideoCompressor.compress(source.path);
    request = await started();
    File(request.outputPath).writeAsStringSync('garbage');
    api.running.remove(task.id)!.complete(); // Success, but nothing readable was registered.
    await expectLater(
      task.result,
      throwsA(isA<VideoCompressException>().having((e) => e.message, 'message', contains('cannot be read'))),
    );
    expect(File(request.outputPath).existsSync(), isFalse);
  });

  test('a paused progress listener does not hold back the result', () async {
    final task = VideoCompressor.compress('/in.mp4');
    final subscription = task.progress.listen((_) {})..pause();
    await started();
    api.complete(task.id);
    await task.result.timeout(const Duration(seconds: 1));
    await subscription.cancel();
  });

  test('copyWith can remove a limit', () {
    const options = CompressOptions(maxShortSide: 720, maxFrameRate: 30);
    final copy = options.copyWith(maxShortSide: null, includeAudio: false);
    expect((copy.maxShortSide, copy.maxFrameRate, copy.includeAudio), (null, 30, false));
    expect(options.copyWith().maxShortSide, 720);
  });
}
