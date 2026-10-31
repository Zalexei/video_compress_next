import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_compress_next/src/video_compressor.dart'
    show VideoCompressor;
import 'package:video_compress_next/video_compress.dart';

import 'fake_host_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late FakeHostApi api;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('vcn_compat');
    api = FakeHostApi(cacheDir: temp.path)
      ..files['/in.mp4'] = videoInfo('/in.mp4', frameRate: 60)
      ..outputInfo = (r) => videoInfo(r.outputPath,
          width: r.width!, height: r.height!, fileSize: 1234);
    VideoCompressor.hostApi = api;
    VideoCompress.dispose();
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('VideoQuality keeps the names and order of video_compress', () {
    expect(VideoQuality.values.map((q) => q.name), [
      'DefaultQuality',
      'LowQuality',
      'MediumQuality',
      'HighestQuality',
      'Res640x480Quality',
      'Res960x540Quality',
      'Res1280x720Quality',
      'Res1920x1080Quality',
    ]);
    expect(VideoQuality.DefaultQuality.options.maxShortSide, 720);
    expect(VideoQuality.Res640x480Quality.options.maxLongSide, 640);
  });

  test('compressVideo maps the old arguments and reports progress 0 to 100',
      () async {
    final progress = <double>[];
    final subscription =
        VideoCompress.compressProgress$.subscribe(progress.add);

    final future = VideoCompress.compressVideo(
      '/in.mp4',
      quality: VideoQuality.LowQuality,
      startTime: 2,
      duration: 3,
      includeAudio: false,
      frameRate: 24,
    );
    expect(VideoCompress.isCompressing, isTrue);
    await pumpEventQueue();
    final request = api.requests.single;
    expect((request.width, request.height), (640, 360));
    expect((request.startMs, request.endMs), (2000, 5000));
    expect(request.includeAudio, isFalse);
    expect(request.maxFrameRate, 24);

    await sendProgress(request.taskId, 0.5);
    api.complete(request.taskId);
    final info = await future;
    await pumpEventQueue();

    final finalPath = request.outputPath.replaceAll('.part.mp4', '');
    expect(info!.path, finalPath);
    expect(info.file!.path, finalPath);
    expect(info.isCancel, isFalse);
    expect(info.filesize, 1234);
    expect(info.duration, 10000.0);
    expect((info.width, info.height), (640, 360));
    expect(progress, [50.0, 100.0]);
    expect(VideoCompress.isCompressing, isFalse);
    subscription.unsubscribe();
  });

  test('a second compression while one runs throws StateError', () async {
    final first = VideoCompress.compressVideo('/in.mp4');
    expect(() => VideoCompress.compressVideo('/in.mp4'), throwsStateError);
    await pumpEventQueue();
    api.complete(api.requests.single.taskId);
    await first;
  });

  test('cancelCompression makes compressVideo return null', () async {
    final future = VideoCompress.compressVideo('/in.mp4');
    await pumpEventQueue();
    await VideoCompress.cancelCompression();
    expect(await future, isNull);
    expect(api.cancelled, hasLength(1));
    expect(VideoCompress.isCompressing, isFalse);
  });

  test('cancelCompression still works after dispose', () async {
    final future = VideoCompress.compressVideo('/in.mp4');
    await pumpEventQueue();
    VideoCompress.dispose();
    await VideoCompress.cancelCompression();
    expect(await future, isNull);
    expect(api.cancelled, hasLength(1));
  });

  test('a failed compression returns null like video_compress did', () async {
    expect(await VideoCompress.compressVideo('/missing.mp4'), isNull);
    expect(VideoCompress.isCompressing, isFalse);
  });

  test('getMediaInfo fills the old fields', () async {
    api.files['/portrait.mp4'] =
        videoInfo('/portrait.mp4', width: 1080, height: 1920, rotation: 90);
    final info = await VideoCompress.getMediaInfo('/portrait.mp4');
    expect((info.width, info.height, info.orientation), (1080, 1920, 90));
    expect(info.filesize, 20000000);
    expect(info.duration, 10000.0);
    expect(info.title, '');
  });

  test('thumbnails: bytes capped at 512 px, files named after the video',
      () async {
    final bytes = await VideoCompress.getByteThumbnail('/in.mp4',
        quality: 50, position: 1500);
    expect(bytes, isNotNull);
    expect(api.lastThumbnail!.maxSide, 512);
    expect(api.lastThumbnail!.positionMs, 1500);
    expect(api.lastThumbnail!.quality, 50);

    expect(await VideoCompress.getByteThumbnail('/missing.mp4'), isNull);

    final file = await VideoCompress.getFileThumbnail('/in.mp4');
    expect(file.path, '${temp.path}/in.jpg');
    expect(file.existsSync(), isTrue);
  });

  test('MediaInfo JSON round trip', () {
    final info = MediaInfo.fromJson(<String, dynamic>{
      'path': '/a.mp4',
      'title': 't',
      'author': 'a',
      'width': 640,
      'height': 360,
      'orientation': 90,
      'filesize': 100,
      'duration': 1500.5,
      'isCancel': false,
    });
    final json = jsonDecode(jsonEncode(info.toJson())) as Map<String, dynamic>;
    final again = MediaInfo.fromJson(json);
    expect((
      again.width,
      again.height,
      again.orientation,
      again.filesize,
      again.duration
    ), (
      640,
      360,
      90,
      100,
      1500.5
    ));
    expect(again.file!.path, '/a.mp4');
  });
}
