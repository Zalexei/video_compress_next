// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.

/// Codec of the compressed video. Audio is always AAC.
enum VideoCodec {
  /// Plays everywhere.
  h264,

  /// About a third smaller at the same quality. Every iPhone since 2017 and
  /// most Android phones since 2016 play it, but some browsers and older
  /// Android devices do not. Falls back to the encoder's nearest format if
  /// the device has no HEVC encoder.
  hevc,
}

/// What to make of a video. The defaults give a 720p H.264 file at 30 fps
/// or less, with sound.
class CompressOptions {
  const CompressOptions({
    this.maxShortSide = 720,
    this.maxLongSide,
    this.videoBitrate,
    this.maxFrameRate = 30,
    this.includeAudio = true,
    this.trimStart,
    this.trimEnd,
    this.codec = VideoCodec.h264,
    this.deleteOrigin = false,
    this.outputPath,
  })  : assert(maxShortSide == null || maxShortSide > 0),
        assert(maxLongSide == null || maxLongSide > 0),
        assert(videoBitrate == null || videoBitrate > 0),
        assert(maxFrameRate == null || maxFrameRate > 0);

  /// The shorter side of the picture is scaled down to this many pixels.
  /// A smaller video is never scaled up. Null sets no limit.
  final int? maxShortSide;

  /// The longer side of the picture is scaled down to this many pixels.
  /// Null sets no limit.
  final int? maxLongSide;

  /// Video bits per second. Null picks a bitrate from the output size and
  /// frame rate, never above the source's.
  final int? videoBitrate;

  /// Frames above this rate are dropped; a slower video is not sped up.
  /// Null keeps every frame.
  ///
  /// On Android, Media3 drops frames only when the source is about 1.5 times
  /// the cap or more: 60 fps becomes 30 and 50 fps becomes 25, but 30 fps
  /// capped at 24 stays 30. iOS keeps to the cap exactly.
  final int? maxFrameRate;

  /// Keeps the sound, re-encoded to AAC. False writes a silent video.
  final bool includeAudio;

  /// Where the output starts in the source. Null starts at the beginning.
  final Duration? trimStart;

  /// Where the output ends in the source. Null runs to the end.
  final Duration? trimEnd;

  /// Codec of the output video; see [VideoCodec].
  final VideoCodec codec;

  /// Deletes the source file after a successful compression. Only works for
  /// plain file paths, not `content://` URIs.
  final bool deleteOrigin;

  /// Where to write the result. Null writes a new file in the plugin's
  /// cache folder, see [VideoCompressor.deleteAllCache].
  final String? outputPath;

  /// A copy with the given fields changed. Passing null for a limit, a trim
  /// point or the output path removes it: `copyWith(maxFrameRate: null)`.
  CompressOptions copyWith({
    Object? maxShortSide = _unchanged,
    Object? maxLongSide = _unchanged,
    Object? videoBitrate = _unchanged,
    Object? maxFrameRate = _unchanged,
    bool? includeAudio,
    Object? trimStart = _unchanged,
    Object? trimEnd = _unchanged,
    VideoCodec? codec,
    bool? deleteOrigin,
    Object? outputPath = _unchanged,
  }) {
    T? pick<T>(Object? value, T? current) =>
        identical(value, _unchanged) ? current : value as T?;
    return CompressOptions(
      maxShortSide: pick(maxShortSide, this.maxShortSide),
      maxLongSide: pick(maxLongSide, this.maxLongSide),
      videoBitrate: pick(videoBitrate, this.videoBitrate),
      maxFrameRate: pick(maxFrameRate, this.maxFrameRate),
      includeAudio: includeAudio ?? this.includeAudio,
      trimStart: pick(trimStart, this.trimStart),
      trimEnd: pick(trimEnd, this.trimEnd),
      codec: codec ?? this.codec,
      deleteOrigin: deleteOrigin ?? this.deleteOrigin,
      outputPath: pick(outputPath, this.outputPath),
    );
  }

  static const Object _unchanged = Object();
}
