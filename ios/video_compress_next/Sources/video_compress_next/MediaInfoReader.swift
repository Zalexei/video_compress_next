// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import AVFoundation

/// Reads the container metadata without decoding any frame.
enum MediaInfoReader {
  static func read(_ path: String) throws -> NativeMediaInfo {
    let fileSize = try Sources.fileSize(path)
    let asset = AVURLAsset(url: Sources.url(path))
    let track = try Sources.videoTrack(asset, path)
    let size = track.naturalSize.applying(track.preferredTransform)
    let audioTracks = asset.tracks(withMediaType: .audio)
    let durationMs = asset.duration.isNumeric ? Int64((asset.duration.seconds * 1000).rounded()) : 0
    let dataRate = asset.tracks.reduce(Float(0)) { $0 + $1.estimatedDataRate }
    let fps = track.nominalFrameRate

    return NativeMediaInfo(
      path: path,
      width: Int64(abs(size.width).rounded()),
      height: Int64(abs(size.height).rounded()),
      rotation: Sources.rotation(track.preferredTransform),
      durationMs: durationMs,
      fileSize: fileSize,
      hasAudio: !audioTracks.isEmpty,
      bitrate: dataRate > 0 ? Int64(dataRate) : nil,
      frameRate: fps > 0 ? Double(fps) : nil,
      videoMimeType: mimeType(track),
      title: metadata(asset, .commonKeyTitle),
      author: metadata(asset, .commonKeyAuthor) ?? metadata(asset, .commonKeyArtist)
    )
  }

  private static func mimeType(_ track: AVAssetTrack) -> String? {
    guard let description = track.formatDescriptions.first else { return nil }
    switch CMFormatDescriptionGetMediaSubType(description as! CMFormatDescription) {
    case kCMVideoCodecType_H264: return "video/avc"
    case kCMVideoCodecType_HEVC, kCMVideoCodecType_HEVCWithAlpha: return "video/hevc"
    case kCMVideoCodecType_MPEG4Video: return "video/mp4v-es"
    case kCMVideoCodecType_H263: return "video/3gpp"
    case kCMVideoCodecType_AppleProRes422, kCMVideoCodecType_AppleProRes4444: return "video/prores"
    default: return nil
    }
  }

  private static func metadata(_ asset: AVAsset, _ key: AVMetadataKey) -> String? {
    AVMetadataItem.metadataItems(from: asset.commonMetadata, withKey: key, keySpace: .common)
      .first?.stringValue
  }
}
