// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'package:flutter/services.dart';

/// Why an operation failed.
enum VideoCompressError {
  /// The file does not exist or cannot be opened.
  fileNotFound,

  /// The file is not a video the platform can decode, or the encoder cannot
  /// produce the requested format.
  unsupported,

  /// [CompressTask.cancel] was called.
  cancelled,

  /// Anything else; see [VideoCompressException.message].
  failed,
}

class VideoCompressException implements Exception {
  const VideoCompressException(this.error, [this.message]);

  factory VideoCompressException.fromPlatform(PlatformException e) {
    final error = switch (e.code) {
      'file_not_found' => VideoCompressError.fileNotFound,
      'unsupported' => VideoCompressError.unsupported,
      'cancelled' => VideoCompressError.cancelled,
      _ => VideoCompressError.failed,
    };
    // An unknown code is itself the clue (a channel error, an engine that
    // went away), so it stays in the message.
    final message = error == VideoCompressError.failed && e.code != 'failed'
        ? '${e.code}: ${e.message}${e.details == null ? '' : ' (${e.details})'}'
        : e.message;
    return VideoCompressException(error, message);
  }

  final VideoCompressError error;
  final String? message;

  @override
  String toString() => 'VideoCompressException(${error.name}: $message)';
}
