import 'package:flutter_test/flutter_test.dart';
import 'package:video_compress_next/src/planner.dart' show minVideoBitrate;
import 'package:video_compress_next/video_compress_next.dart';

VideoInfo source({
  int width = 1920,
  int height = 1080,
  int? bitrate = 16000000,
  double? frameRate = 30,
}) =>
    VideoInfo(
      path: '/v.mp4',
      width: width,
      height: height,
      rotation: 0,
      duration: const Duration(seconds: 10),
      fileSize: 20000000,
      hasAudio: true,
      bitrate: bitrate,
      frameRate: frameRate,
    );

void main() {
  test('1080p landscape becomes 720p at 0.1 bits per pixel', () {
    expect(
      planEncode(source(), const CompressOptions()),
      const EncodePlan(width: 1280, height: 720, videoBitrate: 2764800),
    );
  });

  test('portrait keeps its orientation', () {
    final plan =
        planEncode(source(width: 1080, height: 1920), const CompressOptions());
    expect((plan.width, plan.height), (720, 1280));
  });

  test(
      'a video that already fits is not resized, and the bitrate never exceeds the source',
      () {
    final plan = planEncode(source(width: 640, height: 360, bitrate: 500000),
        const CompressOptions());
    expect(plan, const EncodePlan(videoBitrate: 500000));
  });

  test('60 fps is dropped to 30 and the bitrate is planned for 30', () {
    final plan = planEncode(source(frameRate: 59.94), const CompressOptions());
    expect(plan.maxFrameRate, 30);
    expect(plan.videoBitrate, 2764800);
  });

  test('a 30 fps source gets no frame drop effect', () {
    expect(
        planEncode(source(frameRate: 30.2), const CompressOptions())
            .maxFrameRate,
        isNull);
  });

  test(
      'unknown frame rate counts as 30 for the bitrate and still sends the cap',
      () {
    final plan = planEncode(source(frameRate: null), const CompressOptions());
    expect(plan.maxFrameRate, 30);
    expect(plan.videoBitrate, 2764800);
  });

  test(
      'HEVC needs a lower bitrate and carries the H.264 one for devices without HEVC',
      () {
    final plan =
        planEncode(source(), const CompressOptions(codec: VideoCodec.hevc));
    expect(plan.videoBitrate, (0.065 * 1280 * 720 * 30).round());
    expect(plan.fallbackVideoBitrate, 2764800);
    expect(planEncode(source(), const CompressOptions()).fallbackVideoBitrate,
        isNull);
    final fixed = planEncode(source(),
        const CompressOptions(codec: VideoCodec.hevc, videoBitrate: 1000000));
    expect(
        (fixed.videoBitrate, fixed.fallbackVideoBitrate), (1000000, 1000000));
  });

  test('odd limits are never passed by rounding', () {
    for (var w = 600; w < 2000; w += 7) {
      for (final limit in [359, 481, 541, 719]) {
        final plan = planEncode(source(width: w, height: 1080),
            CompressOptions(maxShortSide: limit));
        final short = plan.width == null
            ? null
            : (plan.width! < plan.height! ? plan.width : plan.height);
        if (short != null) {
          expect(short, lessThanOrEqualTo(limit),
              reason: '${w}x1080 limit $limit');
        }
      }
    }
  });

  test('unknown picture size leaves the bitrate to the encoder', () {
    expect(
        planEncode(source(width: 0, height: 0), const CompressOptions())
            .videoBitrate,
        isNull);
  });

  test('both limits apply and sides stay even', () {
    // 4:3 at 1440x1080 into 640x480: limited by the long side.
    final plan = planEncode(
      source(width: 1440, height: 1080),
      const CompressOptions(maxShortSide: 480, maxLongSide: 640),
    );
    expect((plan.width, plan.height), (640, 480));

    final odd = planEncode(source(width: 1918, height: 1078),
        const CompressOptions(maxShortSide: 360));
    expect(odd.width! % 2, 0);
    expect(odd.height! % 2, 0);
    expect(odd.height, 360);
  });

  test('an explicit bitrate is kept, even above the source', () {
    final plan = planEncode(
        source(bitrate: 1000000), const CompressOptions(videoBitrate: 4000000));
    expect(plan.videoBitrate, 4000000);
  });

  test('no limits keep the size', () {
    final plan = planEncode(source(),
        const CompressOptions(maxShortSide: null, maxFrameRate: null));
    expect(plan.width, isNull);
    expect(plan.maxFrameRate, isNull);
    expect(plan.videoBitrate, 6220800);
  });

  test('tiny output still gets a usable bitrate', () {
    final plan = planEncode(
        source(width: 160, height: 90, bitrate: null), const CompressOptions());
    expect(plan.videoBitrate, minVideoBitrate);
  });
}
