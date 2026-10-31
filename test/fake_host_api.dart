import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_compress_next/src/messages.g.dart';

/// Stands in for the native side: knows a few files, records requests and
/// finishes compressions when the test says so.
class FakeHostApi extends VideoCompressHostApi {
  FakeHostApi({required this.cacheDir});

  final String cacheDir;
  final Map<String, NativeMediaInfo> files = {};
  final List<NativeCompressRequest> requests = [];
  final List<String> cancelled = [];
  final Map<String, Completer<void>> running = {};

  /// Info returned for any output path written by [compress].
  NativeMediaInfo Function(NativeCompressRequest request)? outputInfo;

  /// Makes the next getMediaInfo wait for this before answering.
  Completer<void>? mediaInfoGate;

  @override
  Future<NativeMediaInfo> getMediaInfo(String path) async {
    await mediaInfoGate?.future;
    final info = files[path];
    if (info == null) throw PlatformException(code: 'file_not_found', message: path);
    return info;
  }

  @override
  Future<void> compress(NativeCompressRequest request) {
    requests.add(request);
    final done = Completer<void>();
    running[request.taskId] = done;
    return done.future;
  }

  /// Finishes the compression [taskId] successfully.
  void complete(String taskId) {
    final request = requests.firstWhere((r) => r.taskId == taskId);
    files[request.outputPath] = outputInfo!(request);
    running.remove(taskId)!.complete();
  }

  void fail(String taskId, String code) {
    running.remove(taskId)!.completeError(PlatformException(code: code, message: 'fake $code'));
  }

  @override
  Future<void> cancel(String taskId) async {
    cancelled.add(taskId);
    final done = running.remove(taskId);
    done?.completeError(PlatformException(code: 'cancelled', message: 'cancelled'));
  }

  @override
  Future<Uint8List> getThumbnail(NativeThumbnailRequest request) async {
    if (!files.containsKey(request.path)) {
      throw PlatformException(code: 'file_not_found', message: request.path);
    }
    lastThumbnail = request;
    return Uint8List.fromList([0xFF, 0xD8, 0xFF, request.quality]);
  }

  NativeThumbnailRequest? lastThumbnail;

  @override
  Future<String> cacheDirectory() async => cacheDir;
}

NativeMediaInfo videoInfo(
  String path, {
  int width = 1920,
  int height = 1080,
  int rotation = 0,
  int durationMs = 10000,
  int fileSize = 20000000,
  int? bitrate = 16000000,
  double? frameRate = 30,
  bool hasAudio = true,
}) =>
    NativeMediaInfo(
      path: path,
      width: width,
      height: height,
      rotation: rotation,
      durationMs: durationMs,
      fileSize: fileSize,
      hasAudio: hasAudio,
      bitrate: bitrate,
      frameRate: frameRate,
      videoMimeType: 'video/avc',
    );

/// Sends a progress update as the native side would.
Future<void> sendProgress(String taskId, double progress) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
    'dev.flutter.pigeon.video_compress_next.VideoCompressFlutterApi.onProgress',
    const StandardMessageCodec().encodeMessage(<Object?>[taskId, progress]),
    (_) {},
  );
}
