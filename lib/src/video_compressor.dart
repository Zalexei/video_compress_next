// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'exception.dart';
import 'messages.g.dart';
import 'options.dart';
import 'planner.dart';
import 'video_info.dart';

/// A running compression.
class CompressTask {
  CompressTask._(this.id, this.result, this._progress, this._cancel);

  final String id;

  /// The compressed file's info. Fails with [VideoCompressException], with
  /// [VideoCompressError.cancelled] after [cancel].
  final Future<VideoInfo> result;

  final StreamController<double> _progress;
  final Future<void> Function() _cancel;

  /// From 0 to 1, never going down. Closes when the task ends.
  Stream<double> get progress => _progress.stream;

  /// Stops the compression and deletes the partial file. Does nothing if the
  /// task already ended.
  Future<void> cancel() => _cancel();
}

/// Compresses videos with the platform's hardware encoders: Media3
/// Transformer on Android, AVFoundation on iOS.
abstract final class VideoCompressor {
  static VideoCompressHostApi _api = VideoCompressHostApi();
  static final Map<String, _TaskState> _tasks = {};
  static bool _receiving = false;
  static int _lastId = 0;

  /// Replaces the platform side in tests.
  @visibleForTesting
  static set hostApi(VideoCompressHostApi api) => _api = api;

  /// Reads the size, length and format of the video at [path], a file path
  /// or (on Android) a `content://` URI.
  static Future<VideoInfo> getMediaInfo(String path) =>
      _guard(() async => VideoInfo.fromNative(await _api.getMediaInfo(path)));

  /// Starts compressing the video at [path]; see [CompressOptions].
  static CompressTask compress(
    String path, {
    CompressOptions options = const CompressOptions(),
  }) {
    _listenForProgress();
    final id = '${DateTime.now().microsecondsSinceEpoch}-${++_lastId}';
    final state = _TaskState();
    _tasks[id] = state;
    Future<void> cancel() async {
      if (state.ended) return;
      state.cancelled = true;
      await _api.cancel(id);
    }

    final result = _run(id, path, options, state);
    return CompressTask._(id, result, state.progress, cancel);
  }

  /// A JPEG of the frame at [position] (a representative frame when null),
  /// with the longer side at most [maxSide] pixels.
  static Future<Uint8List> getThumbnail(
    String path, {
    Duration? position,
    int quality = 90,
    int? maxSide,
  }) {
    assert(quality >= 1 && quality <= 100);
    return _guard(() => _api.getThumbnail(NativeThumbnailRequest(
          path: path,
          positionMs: position?.inMilliseconds ?? -1,
          quality: quality,
          maxSide: maxSide,
        )));
  }

  /// [getThumbnail] written to a JPEG file, by default in the cache folder.
  static Future<File> getThumbnailFile(
    String path, {
    Duration? position,
    int quality = 90,
    int? maxSide,
    String? outputPath,
  }) async {
    final bytes = await getThumbnail(path, position: position, quality: quality, maxSide: maxSide);
    final file = File(outputPath ?? '${await cacheDirectory()}/THUMB_${_stamp()}.jpg');
    return file.writeAsBytes(bytes, flush: true);
  }

  /// The folder where compressed videos and thumbnails go by default.
  static Future<String> cacheDirectory() => _guard(_api.cacheDirectory);

  /// Deletes every file in [cacheDirectory]. Returns false if some could not
  /// be deleted, for example while a compression is writing one.
  static Future<bool> deleteAllCache() async {
    final dir = Directory(await cacheDirectory());
    var ok = true;
    await for (final entry in dir.list()) {
      try {
        await entry.delete(recursive: true);
      } on FileSystemException {
        ok = false;
      }
    }
    return ok;
  }

  static Future<VideoInfo> _run(
    String id,
    String path,
    CompressOptions options,
    _TaskState state,
  ) async {
    try {
      return await _guard(() async {
        final source = await getMediaInfo(path);
        final plan = planEncode(source, options);
        final outputPath = options.outputPath ?? '${await cacheDirectory()}/VID_${_stamp()}.mp4';
        if (state.cancelled) {
          throw const VideoCompressException(VideoCompressError.cancelled, 'Cancelled before start');
        }
        await _api.compress(NativeCompressRequest(
          taskId: id,
          inputPath: path,
          outputPath: outputPath,
          width: plan.width,
          height: plan.height,
          videoBitrate: plan.videoBitrate,
          maxFrameRate: plan.maxFrameRate,
          startMs: options.trimStart?.inMilliseconds,
          endMs: options.trimEnd?.inMilliseconds,
          includeAudio: options.includeAudio,
          codec: NativeVideoCodec.values[options.codec.index],
        ));
        final info = await getMediaInfo(outputPath);
        if (options.deleteOrigin) await _deleteQuietly(path);
        state.report(1);
        return info;
      });
    } finally {
      state.ended = true;
      _tasks.remove(id);
      await state.progress.close();
    }
  }

  static void _listenForProgress() {
    if (_receiving) return;
    _receiving = true;
    VideoCompressFlutterApi.setUp(_ProgressReceiver());
  }

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (e) {
      throw VideoCompressException.fromPlatform(e);
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    if (path.startsWith('content://')) return;
    try {
      await File(path.startsWith('file://') ? Uri.parse(path).toFilePath() : path).delete();
    } on FileSystemException {
      // The compressed file is what matters; a source that is already gone is fine.
    }
  }

  static String _stamp() => '${DateTime.now().millisecondsSinceEpoch}_${++_lastId}';
}

class _TaskState {
  final progress = StreamController<double>.broadcast();
  double _last = 0;
  bool cancelled = false;
  bool ended = false;

  void report(double value) {
    if (ended || progress.isClosed || value <= _last) return;
    _last = value.clamp(0, 1).toDouble();
    progress.add(_last);
  }
}

class _ProgressReceiver implements VideoCompressFlutterApi {
  @override
  void onProgress(String taskId, double progress) =>
      VideoCompressor._tasks[taskId]?.report(progress);
}
