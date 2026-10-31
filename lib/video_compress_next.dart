// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.

/// Video compression with the platform's hardware encoders: AndroidX Media3
/// Transformer on Android, AVFoundation on iOS. No FFmpeg.
///
/// Moving from `video_compress`? Import `package:video_compress_next/video_compress.dart`
/// instead: it has the same classes and methods.
library;

export 'src/exception.dart';
export 'src/options.dart';
export 'src/planner.dart' show EncodePlan, planEncode;
export 'src/video_compressor.dart';
export 'src/video_info.dart';
