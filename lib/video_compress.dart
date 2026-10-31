// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.

/// The API of `video_compress` 3.1.4, so moving over is a change of imports:
///
/// ```dart
/// import 'package:video_compress_next/video_compress.dart';
/// ```
///
/// New code can use `package:video_compress_next/video_compress_next.dart`,
/// which adds typed errors, per-task progress and cancel, HEVC and more.
library;

export 'src/compat/media_info.dart';
export 'src/compat/subscription.dart';
export 'src/compat/video_compressor.dart';
export 'src/compat/video_quality.dart';
