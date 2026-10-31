// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
  /// [VideoCompressError.cancelled] after [cancel]. Await it or handle its
  /// error: a failure left unhandled reaches the zone's error handler.
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
      await _guard(() => _api.cancel(id));
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
    return _guard(() => file.writeAsBytes(bytes, flush: true));
  }

  /// The folder where compressed videos and thumbnails go by default.
  static Future<String> cacheDirectory() => _guard(_api.cacheDirectory);

  /// Deletes every file in [cacheDirectory] except those that running
  /// compressions are writing. Returns false if some could not be deleted.
  static Future<bool> deleteAllCache() async {
    final dir = Directory(await cacheDirectory());
    final busy = {for (final task in _tasks.values) if (task.partPath != null) task.partPath!};
    var ok = true;
    await _guard(() async {
      await for (final entry in dir.list()) {
        if (busy.contains(entry.path)) continue;
        try {
          await entry.delete(recursive: true);
        } on FileSystemException {
          ok = false;
        }
      }
    });
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
        if (_samePath(path, outputPath)) {
          throw VideoCompressException(
              VideoCompressError.failed, 'The output path is the input file: $outputPath');
        }
        // The platform writes next to the output and the file is renamed on
        // success, so a failed or cancelled compression leaves whatever is at
        // outputPath alone.
        final partPath = '$outputPath.part.mp4';
        state.partPath = partPath;
        state.throwIfCancelled();
        await _api.compress(NativeCompressRequest(
          taskId: id,
          inputPath: path,
          outputPath: partPath,
          width: plan.width,
          height: plan.height,
          videoBitrate: plan.videoBitrate,
          fallbackVideoBitrate: plan.fallbackVideoBitrate,
          maxFrameRate: plan.maxFrameRate,
          startMs: options.trimStart?.inMilliseconds,
          endMs: options.trimEnd?.inMilliseconds,
          includeAudio: options.includeAudio,
          codec: NativeVideoCodec.values[options.codec.index],
        ));
        // cancel() may have come after the platform finished.
        state.throwIfCancelled();
        await _checkOutput(source, options, partPath);
        state.throwIfCancelled();
        await File(partPath).rename(outputPath);
        state.partPath = null;
        final info = await getMediaInfo(outputPath);
        if (state.cancelled) {
          await _deleteIfExists(outputPath);
          state.throwIfCancelled();
        }
        if (options.deleteOrigin) await _deleteOrigin(path);
        state.report(1);
        return info;
      });
    } on VideoCompressException catch (e) {
      // After cancel() any failure is reported as the cancellation it caused.
      if (state.cancelled && e.error != VideoCompressError.cancelled) {
        throw const VideoCompressException(VideoCompressError.cancelled, 'The compression was cancelled.');
      }
      rethrow;
    } finally {
      final partPath = state.partPath;
      if (partPath != null) await _deleteIfExists(partPath);
      state.ended = true;
      _tasks.remove(id);
      // Not awaited: the done event waits for paused listeners.
      unawaited(state.progress.close());
    }
  }

  /// Fails, instead of handing back the file, if the platform reported
  /// success but wrote something unreadable or clearly shorter than asked.
  static Future<void> _checkOutput(VideoInfo source, CompressOptions options, String path) async {
    final VideoInfo written;
    try {
      written = await getMediaInfo(path);
    } on VideoCompressException catch (e) {
      throw VideoCompressException(VideoCompressError.failed, 'The compressed file cannot be read: ${e.message}');
    }
    final total = source.duration;
    if (total <= Duration.zero) return;
    final end = options.trimEnd == null || options.trimEnd! > total ? total : options.trimEnd!;
    final expected = end - (options.trimStart ?? Duration.zero);
    if (expected <= Duration.zero) return;
    final slack = Duration(milliseconds: math.max(1000, expected.inMilliseconds ~/ 10));
    if (written.duration < expected - slack) {
      throw VideoCompressException(
        VideoCompressError.failed,
        'The compressed video is ${written.duration} long instead of about $expected',
      );
    }
  }

  static void _listenForProgress() {
    if (_receiving) return;
    try {
      VideoCompressFlutterApi.setUp(_ProgressReceiver());
      _receiving = true;
    } on UnsupportedError {
      // A background isolate cannot receive calls from the platform: the
      // compression still works, only without progress.
    }
  }

  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on PlatformException catch (e) {
      throw VideoCompressException.fromPlatform(e);
    } on FileSystemException catch (e) {
      throw VideoCompressException(VideoCompressError.failed, '$e');
    }
  }

  static bool _samePath(String input, String output) {
    if (input.startsWith('content://')) return false;
    try {
      final a = File(_filePath(input)).absolute;
      final b = File(_filePath(output)).absolute;
      if (a.path == b.path) return true;
      return b.existsSync() && a.resolveSymbolicLinksSync() == b.resolveSymbolicLinksSync();
    } on Object {
      return false;
    }
  }

  static String _filePath(String path) =>
      path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;

  static Future<void> _deleteOrigin(String path) async {
    if (path.startsWith('content://')) return;
    try {
      await File(_filePath(path)).delete();
    } on Object catch (e) {
      // The compressed file is what matters; say why the source is still there.
      debugPrint('video_compress_next: could not delete the source $path: $e');
    }
  }

  static Future<void> _deleteIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Nothing more to do with a leftover partial file.
    }
  }

  static String _stamp() => '${DateTime.now().millisecondsSinceEpoch}_${++_lastId}';
}

class _TaskState {
  final progress = StreamController<double>.broadcast();
  double _last = 0;
  bool cancelled = false;
  bool ended = false;

  /// The file the platform is writing, until it is renamed.
  String? partPath;

  void throwIfCancelled() {
    if (cancelled) {
      throw const VideoCompressException(VideoCompressError.cancelled, 'The compression was cancelled.');
    }
  }

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
