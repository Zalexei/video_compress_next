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
  final int? maxFrameRate;

  final bool includeAudio;

  /// Where the output starts in the source. Null starts at the beginning.
  final Duration? trimStart;

  /// Where the output ends in the source. Null runs to the end.
  final Duration? trimEnd;

  final VideoCodec codec;

  /// Deletes the source file after a successful compression. Only works for
  /// plain file paths, not `content://` URIs.
  final bool deleteOrigin;

  /// Where to write the result. Null writes a new file in the plugin's
  /// cache folder, see [VideoCompressor.deleteAllCache].
  final String? outputPath;

  CompressOptions copyWith({
    int? maxShortSide,
    int? maxLongSide,
    int? videoBitrate,
    int? maxFrameRate,
    bool? includeAudio,
    Duration? trimStart,
    Duration? trimEnd,
    VideoCodec? codec,
    bool? deleteOrigin,
    String? outputPath,
  }) =>
      CompressOptions(
        maxShortSide: maxShortSide ?? this.maxShortSide,
        maxLongSide: maxLongSide ?? this.maxLongSide,
        videoBitrate: videoBitrate ?? this.videoBitrate,
        maxFrameRate: maxFrameRate ?? this.maxFrameRate,
        includeAudio: includeAudio ?? this.includeAudio,
        trimStart: trimStart ?? this.trimStart,
        trimEnd: trimEnd ?? this.trimEnd,
        codec: codec ?? this.codec,
        deleteOrigin: deleteOrigin ?? this.deleteOrigin,
        outputPath: outputPath ?? this.outputPath,
      );
}
