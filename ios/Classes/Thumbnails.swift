// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import AVFoundation
import UIKit

enum Thumbnails {
  static func jpeg(_ request: NativeThumbnailRequest) throws -> Data {
    _ = try Sources.fileSize(request.path)
    let asset = AVURLAsset(url: Sources.url(request.path))
    let track = try Sources.videoTrack(asset, request.path)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    if let maxSide = request.maxSide {
      generator.maximumSize = CGSize(width: Int(maxSide), height: Int(maxSide))
    }
    var time = CMTime.zero
    if request.positionMs >= 0 {
      // The default tolerance is unlimited and returns a frame seconds away
      // from the position; with none, a time past the end throws, so the
      // position is kept inside the last frame.
      generator.requestedTimeToleranceBefore = .zero
      generator.requestedTimeToleranceAfter = .zero
      let frame = 1 / Double(track.nominalFrameRate > 0 ? track.nominalFrameRate : 30)
      let last = max(asset.duration.seconds - frame, 0)
      time = CMTime(seconds: min(Double(request.positionMs) / 1000, last), preferredTimescale: 600)
    }
    let image: CGImage
    do {
      image = try generator.copyCGImage(at: time, actualTime: nil)
    } catch {
      throw PigeonError(
        code: "unsupported", message: "Cannot read a frame of \(request.path): \(error)", details: nil)
    }
    let quality = CGFloat(min(max(request.quality, 1), 100)) / 100
    guard let data = UIImage(cgImage: image).jpegData(compressionQuality: quality) else {
      throw PigeonError(code: "failed", message: "JPEG encoding failed", details: nil)
    }
    return data
  }
}
