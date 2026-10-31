// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import AVFoundation

/// Paths from Dart are plain file paths or `file://` URLs.
enum Sources {
  static func url(_ path: String) -> URL {
    if path.hasPrefix("file://"), let url = URL(string: path) { return url }
    return URL(fileURLWithPath: path)
  }

  static func fileSize(_ path: String) throws -> Int64 {
    let url = url(path)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw PigeonError(code: "file_not_found", message: "No file at \(path)", details: nil)
    }
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
  }

  static func videoTrack(_ asset: AVAsset, _ path: String) throws -> AVAssetTrack {
    guard let track = asset.tracks(withMediaType: .video).first else {
      throw PigeonError(code: "unsupported", message: "No video track in \(path)", details: nil)
    }
    return track
  }

  /// Rotation in degrees (0, 90, 180 or 270) stored in a track's transform.
  static func rotation(_ transform: CGAffineTransform) -> Int64 {
    let degrees = Int64((atan2(transform.b, transform.a) * 180 / .pi).rounded())
    return ((degrees % 360) + 360) % 360
  }
}
