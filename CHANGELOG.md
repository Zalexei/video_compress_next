## 0.1.0

* First version, not published yet.
* Android: compression with AndroidX Media3 Transformer (1.9.4 by default, any
  1.x through `videoCompressNextMedia3Version`), media info and thumbnails
  with `MediaMetadataRetriever`.
* iOS: compression with `AVAssetReader` and `AVAssetWriter`, media info with
  `AVURLAsset`, thumbnails with `AVAssetImageGenerator`.
* `package:video_compress_next/video_compress.dart`: the `video_compress`
  3.1.4 API on top of the new engine.
