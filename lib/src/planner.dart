// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'dart:math' as math;

import 'options.dart';
import 'video_info.dart';

/// Exact encoder settings for one compression. Null fields keep the source's
/// value or leave the choice to the encoder.
class EncodePlan {
  const EncodePlan({
    this.width,
    this.height,
    this.videoBitrate,
    this.fallbackVideoBitrate,
    this.maxFrameRate,
  });

  final int? width;
  final int? height;
  final int? videoBitrate;

  /// For HEVC: the bitrate to use if the device has no HEVC encoder and
  /// H.264 is used instead.
  final int? fallbackVideoBitrate;

  final int? maxFrameRate;

  @override
  bool operator ==(Object other) =>
      other is EncodePlan &&
      other.width == width &&
      other.height == height &&
      other.videoBitrate == videoBitrate &&
      other.fallbackVideoBitrate == fallbackVideoBitrate &&
      other.maxFrameRate == maxFrameRate;

  @override
  int get hashCode => Object.hash(width, height, videoBitrate, fallbackVideoBitrate, maxFrameRate);

  @override
  String toString() =>
      'EncodePlan(${width}x$height, $videoBitrate bps (H.264 fallback $fallbackVideoBitrate), '
      'max $maxFrameRate fps)';
}

/// Bits per pixel per frame: about 2.8 Mbps for 720p at 30 fps in H.264,
/// which looks clean on a phone. HEVC needs about a third less.
const double h264BitsPerPixel = 0.1;
const double hevcBitsPerPixel = 0.065;

/// Below this the picture falls apart whatever the size.
const int minVideoBitrate = 200000;

/// Plans the output of compressing [source] with [options]. A pure function,
/// so the same plan comes out on every platform.
EncodePlan planEncode(VideoInfo source, CompressOptions options) {
  final size = _outputSize(source.width, source.height, options);
  final sourceFps = source.frameRate;
  final cap = options.maxFrameRate;
  // A frame drop effect only when it would drop something. With an unknown
  // frame rate the cap is passed on: dropping keeps every frame of a slower
  // video, and a faster one must not slip through.
  final dropFrames = cap != null && (sourceFps == null || sourceFps > cap + 0.5);
  final outputFps = math.min(sourceFps ?? 30.0, cap?.toDouble() ?? double.infinity);
  final pixels = (size?.$1 ?? source.width) * (size?.$2 ?? source.height);

  int? autoBitrate(double bitsPerPixel) {
    // Without a known picture size the encoder's own choice beats a guess.
    if (pixels <= 0) return null;
    var bitrate = math.max(minVideoBitrate, (bitsPerPixel * pixels * outputFps).round());
    final sourceBitrate = source.bitrate;
    if (sourceBitrate != null && sourceBitrate > 0) {
      bitrate = math.min(bitrate, sourceBitrate);
    }
    return bitrate;
  }

  final hevc = options.codec == VideoCodec.hevc;
  return EncodePlan(
    width: size?.$1,
    height: size?.$2,
    videoBitrate: options.videoBitrate ?? autoBitrate(hevc ? hevcBitsPerPixel : h264BitsPerPixel),
    fallbackVideoBitrate: hevc ? options.videoBitrate ?? autoBitrate(h264BitsPerPixel) : null,
    maxFrameRate: dropFrames ? cap : null,
  );
}

/// The displayed size scaled down to fit both limits, with even sides as
/// encoders need; null when the source already fits.
(int, int)? _outputSize(int width, int height, CompressOptions options) {
  if (width <= 0 || height <= 0) return null;
  final shortSide = math.min(width, height);
  final longSide = math.max(width, height);
  var scale = 1.0;
  final maxShort = options.maxShortSide;
  final maxLong = options.maxLongSide;
  if (maxShort != null) scale = math.min(scale, maxShort / shortSide);
  if (maxLong != null) scale = math.min(scale, maxLong / longSide);
  if (scale >= 1.0) return null;
  int even(double value) => math.max(2, (value / 2).round() * 2);
  // Rounding to even can pass an odd limit by a pixel; such a side drops to
  // the even number below the limit.
  int fit(int side, int original) {
    final isShort = original == shortSide;
    final isLong = original == longSide;
    if (isShort && maxShort != null && side > maxShort) side = math.max(2, maxShort ~/ 2 * 2);
    if (isLong && maxLong != null && side > maxLong) side = math.max(2, maxLong ~/ 2 * 2);
    return side;
  }

  return (fit(even(width * scale), width), fit(even(height * scale), height));
}
