// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import AVFoundation
import UIKit

enum Thumbnails {
  static func jpeg(_ request: NativeThumbnailRequest) throws -> Data {
    _ = try Sources.fileSize(request.path)
    let asset = AVURLAsset(url: Sources.url(request.path))
    _ = try Sources.videoTrack(asset, request.path)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    if let maxSide = request.maxSide {
      generator.maximumSize = CGSize(width: Int(maxSide), height: Int(maxSide))
    }
    let time = request.positionMs < 0
      ? CMTime.zero : CMTime(value: request.positionMs, timescale: 1000)
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
