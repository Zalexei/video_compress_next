// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
// ignore_for_file: non_constant_identifier_names

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../exception.dart';
import '../video_compressor.dart';
import 'media_info.dart';
import 'subscription.dart';
import 'video_quality.dart';

/// Thumbnails of `video_compress` were at most 512 pixels on the longer side.
const int _thumbnailMaxSide = 512;

/// The `video_compress` plugin object, on top of [VideoCompressor].
abstract class IVideoCompress {
  final compressProgress$ = ObservableBuilder<double>();

  bool _isCompressing = false;
  CompressTask? _task;

  bool get isCompressing => _isCompressing;

  @protected
  void setProcessingStatus(bool status) {
    _isCompressing = status;
  }
}

class _VideoCompressImpl extends IVideoCompress {
  _VideoCompressImpl._();

  static _VideoCompressImpl? _instance;

  static _VideoCompressImpl get instance => _instance ??= _VideoCompressImpl._();

  static void _dispose() {
    _instance = null;
  }
}

/// The same global as `video_compress`: `VideoCompress.compressVideo(...)`.
IVideoCompress get VideoCompress => _VideoCompressImpl.instance;

extension Compress on IVideoCompress {
  void dispose() {
    _VideoCompressImpl._dispose();
  }

  /// JPEG bytes of the frame at [position] milliseconds (-1 for a
  /// representative frame), at JPEG [quality] 1 to 100. Null if the frame
  /// cannot be read.
  Future<Uint8List?> getByteThumbnail(
    String path, {
    int quality = 100,
    int position = -1,
  }) async {
    try {
      return await VideoCompressor.getThumbnail(
        path,
        position: position < 0 ? null : Duration(milliseconds: position),
        quality: quality.clamp(1, 100),
        maxSide: _thumbnailMaxSide,
      );
    } on VideoCompressException catch (e) {
      _log('getByteThumbnail', e);
      return null;
    }
  }

  /// [getByteThumbnail] written to `<video name>.jpg` in the cache folder.
  Future<File> getFileThumbnail(
    String path, {
    int quality = 100,
    int position = -1,
  }) async {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    return VideoCompressor.getThumbnailFile(
      path,
      position: position < 0 ? null : Duration(milliseconds: position),
      quality: quality.clamp(1, 100),
      maxSide: _thumbnailMaxSide,
      outputPath: '${await VideoCompressor.cacheDirectory()}/$base.jpg',
    );
  }

  Future<MediaInfo> getMediaInfo(String path) async =>
      MediaInfo.fromVideoInfo(await VideoCompressor.getMediaInfo(path));

  /// Compresses the video at [path]. [startTime] and [duration] are in
  /// seconds; [frameRate] is a cap, a slower video is not sped up.
  ///
  /// Returns null when the compression fails or is cancelled, as
  /// `video_compress` did on Android. Progress from 0 to 100 goes to
  /// [IVideoCompress.compressProgress$].
  Future<MediaInfo?> compressVideo(
    String path, {
    VideoQuality quality = VideoQuality.DefaultQuality,
    bool deleteOrigin = false,
    int? startTime,
    int? duration,
    bool? includeAudio,
    int frameRate = 30,
  }) async {
    if (isCompressing) {
      throw StateError('''VideoCompress Error: 
      Method: compressVideo
      Already have a compression process, you need to wait for the process to finish or stop it''');
    }
    if (compressProgress$.notSubscribed) {
      debugPrint('''VideoCompress: You can try to subscribe to the 
      compressProgress\$ stream to know the compressing state.''');
    }

    final start = startTime == null ? null : Duration(seconds: startTime);
    final end = duration == null ? null : (start ?? Duration.zero) + Duration(seconds: duration);
    final options = quality.options.copyWith(
      deleteOrigin: deleteOrigin,
      includeAudio: includeAudio ?? true,
      maxFrameRate: frameRate,
      trimStart: start,
      trimEnd: end,
    );

    // ignore: invalid_use_of_protected_member
    setProcessingStatus(true);
    final task = VideoCompressor.compress(path, options: options);
    _task = task;
    final listening = task.progress.listen((p) => compressProgress$.next(p * 100));
    try {
      final info = await task.result;
      return MediaInfo.fromVideoInfo(info, isCancel: false);
    } on VideoCompressException catch (e) {
      if (e.error != VideoCompressError.cancelled) _log('compressVideo', e);
      return null;
    } finally {
      await listening.cancel();
      _task = null;
      // ignore: invalid_use_of_protected_member
      setProcessingStatus(false);
    }
  }

  /// Stops the running compression; [compressVideo] then returns null.
  Future<void> cancelCompression() async {
    await _task?.cancel();
  }

  /// Deletes the plugin's cache folder contents, compressed videos included.
  Future<bool?> deleteAllCache() => VideoCompressor.deleteAllCache();

  /// Kept for source compatibility; the plugin has no log levels.
  Future<void> setLogLevel(int logLevel) async {}
}

void _log(String method, VideoCompressException e) {
  debugPrint('''Error from VideoCompress: 
      Method: $method
      $e''');
}
