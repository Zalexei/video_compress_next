// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
// ignore_for_file: constant_identifier_names

import '../options.dart';

/// The quality levels of `video_compress`, with the same names and order.
enum VideoQuality {
  DefaultQuality,
  LowQuality,
  MediumQuality,
  HighestQuality,
  Res640x480Quality,
  Res960x540Quality,
  Res1280x720Quality,
  Res1920x1080Quality,
}

extension VideoQualityOptions on VideoQuality {
  /// The size limits this level stands for. They follow what `video_compress`
  /// did on Android, where it limited the shorter side; the bitrate now comes
  /// from the output size instead of being fixed.
  CompressOptions get options => switch (this) {
        VideoQuality.DefaultQuality => const CompressOptions(maxShortSide: 720),
        VideoQuality.LowQuality => const CompressOptions(maxShortSide: 360),
        VideoQuality.MediumQuality => const CompressOptions(maxShortSide: 640),
        // video_compress kept the size and fixed 3.7 Mbps, which made 4K blocky.
        VideoQuality.HighestQuality => const CompressOptions(maxShortSide: 1080),
        VideoQuality.Res640x480Quality =>
          const CompressOptions(maxShortSide: 480, maxLongSide: 640),
        VideoQuality.Res960x540Quality =>
          const CompressOptions(maxShortSide: 540, maxLongSide: 960),
        VideoQuality.Res1280x720Quality =>
          const CompressOptions(maxShortSide: 720, maxLongSide: 1280),
        VideoQuality.Res1920x1080Quality =>
          const CompressOptions(maxShortSide: 1080, maxLongSide: 1920),
      };
}
