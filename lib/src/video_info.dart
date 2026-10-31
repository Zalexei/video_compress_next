// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'messages.g.dart';

/// What the platform knows about a video file.
class VideoInfo {
  const VideoInfo({
    required this.path,
    required this.width,
    required this.height,
    required this.rotation,
    required this.duration,
    required this.fileSize,
    required this.hasAudio,
    this.bitrate,
    this.frameRate,
    this.videoMimeType,
    this.title,
    this.author,
  });

  factory VideoInfo.fromNative(NativeMediaInfo info) => VideoInfo(
        path: info.path,
        width: info.width,
        height: info.height,
        rotation: info.rotation,
        duration: Duration(milliseconds: info.durationMs),
        fileSize: info.fileSize,
        hasAudio: info.hasAudio,
        bitrate: info.bitrate,
        frameRate: info.frameRate,
        videoMimeType: info.videoMimeType,
        title: info.title,
        author: info.author,
      );

  final String path;

  /// Displayed width, with [rotation] already applied.
  final int width;

  /// Displayed height, with [rotation] already applied.
  final int height;

  /// Rotation stored in the file, in degrees: 0, 90, 180 or 270.
  final int rotation;

  final Duration duration;

  /// Bytes.
  final int fileSize;

  final bool hasAudio;

  /// Bits per second of the whole file, video and audio, if the file says.
  final int? bitrate;

  /// Frames per second, if the file says.
  final double? frameRate;

  /// For example `video/avc` or `video/hevc`.
  final String? videoMimeType;

  final String? title;
  final String? author;

  @override
  String toString() => 'VideoInfo($path, ${width}x$height, rotation $rotation, '
      '$duration, $fileSize bytes, bitrate $bitrate, ${frameRate?.toStringAsFixed(2)} fps, '
      '$videoMimeType, audio $hasAudio)';
}
