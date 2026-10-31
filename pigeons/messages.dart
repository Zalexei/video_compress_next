// Contract between Dart and the native side. Regenerate after editing:
//   dart run pigeon --input pigeons/messages.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'video_compress_next',
    kotlinOut:
        'android/src/main/kotlin/io/github/zalexei/video_compress_next/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'io.github.zalexei.video_compress_next'),
    swiftOut: 'ios/video_compress_next/Sources/video_compress_next/Messages.g.swift',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
/// Video codec of the compressed file.
enum NativeVideoCodec { h264, hevc }

/// What the platform knows about a media file.
///
/// [width] and [height] are the displayed size, with [rotation] already
/// applied: a portrait phone video is taller than it is wide.
class NativeMediaInfo {
  NativeMediaInfo({
    required this.path,
    required this.width,
    required this.height,
    required this.rotation,
    required this.durationMs,
    required this.fileSize,
    required this.hasAudio,
  });

  String path;
  int width;
  int height;
  int rotation;
  int durationMs;
  int fileSize;
  bool hasAudio;

  /// Bits per second of the whole file (video and audio).
  int? bitrate;
  double? frameRate;
  String? videoMimeType;
  String? title;
  String? author;
}

/// One compression, already planned on the Dart side: the native code only
/// encodes to exactly these values.
class NativeCompressRequest {
  NativeCompressRequest({
    required this.taskId,
    required this.inputPath,
    required this.outputPath,
    required this.includeAudio,
    required this.codec,
  });

  String taskId;
  String inputPath;
  String outputPath;

  /// Displayed output size; null keeps the input size.
  int? width;
  int? height;

  /// Bits per second; null lets the encoder choose.
  int? videoBitrate;

  /// Used instead of [videoBitrate] when HEVC was asked for but the device
  /// has no HEVC encoder and H.264 is used: H.264 needs more bits.
  int? fallbackVideoBitrate;

  /// Frames above this rate are dropped; null keeps all frames.
  int? maxFrameRate;

  int? startMs;
  int? endMs;
  bool includeAudio;
  NativeVideoCodec codec;
}

class NativeThumbnailRequest {
  NativeThumbnailRequest({
    required this.path,
    required this.positionMs,
    required this.quality,
  });

  String path;

  /// Negative picks a representative frame, as the platform sees fit.
  int positionMs;

  /// JPEG quality from 1 to 100.
  int quality;

  /// The longer side is scaled down to this; null keeps the frame size.
  int? maxSide;
}

@HostApi()
abstract class VideoCompressHostApi {
  @async
  NativeMediaInfo getMediaInfo(String path);

  /// Completes when the file at [NativeCompressRequest.outputPath] is
  /// written. Fails with code `cancelled` after [cancel].
  @async
  void compress(NativeCompressRequest request);

  /// Does nothing if the task already finished.
  void cancel(String taskId);

  @async
  Uint8List getThumbnail(NativeThumbnailRequest request);

  /// Folder for compressed videos and thumbnails, created if missing.
  String cacheDirectory();
}

@FlutterApi()
abstract class VideoCompressFlutterApi {
  /// [progress] goes from 0 to 1.
  void onProgress(String taskId, double progress);
}
