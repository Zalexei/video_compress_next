// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import AVFoundation

/// One compression with AVAssetReader and AVAssetWriter, which, unlike
/// AVAssetExportSession presets, take an exact size, bitrate and codec.
final class CompressJob {
  private let request: NativeCompressRequest
  private let onProgress: (Double) -> Void
  private let onDone: (Result<Void, Error>) -> Void
  private let output: URL
  private let queue = DispatchQueue(label: "video_compress_next.job", qos: .userInitiated)
  private let videoQueue = DispatchQueue(label: "video_compress_next.video", qos: .userInitiated)
  private let audioQueue = DispatchQueue(label: "video_compress_next.audio", qos: .userInitiated)
  private let lock = NSLock()
  private var reader: AVAssetReader?
  private var writer: AVAssetWriter?
  private var cancelled = false
  private var finished = false

  init(
    request: NativeCompressRequest,
    onProgress: @escaping (Double) -> Void,
    onDone: @escaping (Result<Void, Error>) -> Void
  ) {
    self.request = request
    self.onProgress = onProgress
    self.onDone = onDone
    self.output = URL(fileURLWithPath: request.outputPath)
  }

  func start() {
    queue.async {
      do {
        try self.run()
      } catch {
        self.fail(error)
      }
    }
  }

  func cancel() {
    lock.lock()
    let alreadyOver = cancelled || finished
    cancelled = true
    let reader = self.reader
    let writer = self.writer
    lock.unlock()
    if alreadyOver { return }
    reader?.cancelReading()
    writer?.cancelWriting()
    try? FileManager.default.removeItem(at: output)
    finish(.failure(PigeonError(code: "cancelled", message: "The compression was cancelled.", details: nil)))
  }

  private var isCancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancelled
  }

  private func run() throws {
    _ = try Sources.fileSize(request.inputPath)
    let asset = AVURLAsset(url: Sources.url(request.inputPath))
    let videoTrack = try Sources.videoTrack(asset, request.inputPath)
    let timeRange = try range(asset)

    try? FileManager.default.removeItem(at: output)
    try FileManager.default.createDirectory(
      at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

    let reader = try AVAssetReader(asset: asset)
    reader.timeRange = timeRange
    let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    writer.shouldOptimizeForNetworkUse = true

    let videoOutput = AVAssetReaderTrackOutput(
      track: videoTrack,
      outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
      ])
    videoOutput.alwaysCopiesSampleData = false
    reader.add(videoOutput)
    let videoInput = AVAssetWriterInput(
      mediaType: .video, outputSettings: videoSettings(videoTrack, writer))
    // Frames are encoded as stored and the rotation is kept as metadata.
    videoInput.transform = videoTrack.preferredTransform
    videoInput.expectsMediaDataInRealTime = false
    writer.add(videoInput)

    var audio: (AVAssetReaderTrackOutput, AVAssetWriterInput)?
    if request.includeAudio, let audioTrack = asset.tracks(withMediaType: .audio).first {
      audio = addAudio(audioTrack, reader, writer)
    }

    lock.lock()
    self.reader = reader
    self.writer = writer
    let stop = cancelled
    lock.unlock()
    if stop { return }

    guard reader.startReading() else { throw failure(reader.error, "Cannot read the video") }
    guard writer.startWriting() else { throw failure(writer.error, "Cannot write the video") }
    writer.startSession(atSourceTime: timeRange.start)

    let group = DispatchGroup()
    pumpVideo(videoOutput, videoInput, timeRange, group)
    if let (audioOutput, audioInput) = audio {
      pump(audioOutput, audioInput, on: audioQueue, group)
    }
    group.notify(queue: queue) {
      if self.isCancelled { return }
      if reader.status == .failed {
        writer.cancelWriting()
        self.fail(self.failure(reader.error, "Reading the video failed"))
        return
      }
      writer.finishWriting {
        if writer.status == .completed {
          self.onProgress(1)
          self.finish(.success(()))
        } else {
          self.fail(self.failure(writer.error, "Writing the video failed"))
        }
      }
    }
  }

  private func range(_ asset: AVAsset) throws -> CMTimeRange {
    let duration = asset.duration
    let start = request.startMs.map { CMTime(value: $0, timescale: 1000) } ?? .zero
    var end = request.endMs.map { CMTime(value: $0, timescale: 1000) } ?? duration
    if duration.isNumeric && end > duration { end = duration }
    guard start < end else {
      throw PigeonError(code: "failed", message: "The trim range is empty", details: nil)
    }
    return CMTimeRange(start: start, end: end)
  }

  private func videoSettings(_ track: AVAssetTrack, _ writer: AVAssetWriter) -> [String: Any] {
    let sideways = Sources.rotation(track.preferredTransform) % 180 != 0
    var width = Int(track.naturalSize.width.rounded())
    var height = Int(track.naturalSize.height.rounded())
    // The requested size is as displayed; the encoder gets frames as stored.
    if let w = request.width, let h = request.height {
      width = Int(sideways ? h : w)
      height = Int(sideways ? w : h)
    }
    var compression: [String: Any] = [AVVideoMaxKeyFrameIntervalDurationKey: 2]
    if let bitrate = request.videoBitrate { compression[AVVideoAverageBitRateKey] = bitrate }
    if let fps = request.maxFrameRate { compression[AVVideoExpectedSourceFrameRateKey] = fps }
    var settings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
      AVVideoCompressionPropertiesKey: compression,
      // H.264 has no HDR that plays everywhere; tag the output as plain SDR.
      AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
      ],
    ]
    if request.codec == .hevc {
      var hevc = settings
      hevc[AVVideoCodecKey] = AVVideoCodecType.hevc
      if writer.canApply(outputSettings: hevc, forMediaType: .video) { settings = hevc }
    }
    return settings
  }

  private func addAudio(
    _ track: AVAssetTrack, _ reader: AVAssetReader, _ writer: AVAssetWriter
  ) -> (AVAssetReaderTrackOutput, AVAssetWriterInput)? {
    var sampleRate = 44_100.0
    var channels: UInt32 = 2
    if let description = track.formatDescriptions.first,
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
        description as! CMAudioFormatDescription)?.pointee
    {
      if asbd.mSampleRate > 0 { sampleRate = min(asbd.mSampleRate, 48_000) }
      if asbd.mChannelsPerFrame > 0 { channels = min(asbd.mChannelsPerFrame, 2) }
    }
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channels,
      ])
    var layout = AudioChannelLayout()
    layout.mChannelLayoutTag = channels == 1 ? kAudioChannelLayoutTag_Mono : kAudioChannelLayoutTag_Stereo
    let input = AVAssetWriterInput(
      mediaType: .audio,
      outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channels,
        AVEncoderBitRateKey: channels == 1 ? 64_000 : 128_000,
        AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
      ])
    input.expectsMediaDataInRealTime = false
    guard reader.canAdd(output), writer.canAdd(input) else { return nil }
    reader.add(output)
    writer.add(input)
    return (output, input)
  }

  private func pumpVideo(
    _ output: AVAssetReaderTrackOutput, _ input: AVAssetWriterInput,
    _ timeRange: CMTimeRange, _ group: DispatchGroup
  ) {
    let duration = max(timeRange.duration.seconds, 0.001)
    // Keeps a frame only if it comes at least 90 % of a frame interval after
    // the last kept one: 60 fps capped at 30 keeps every other frame.
    let minGap = request.maxFrameRate.map { 0.9 / Double($0) }
    var lastKept: Double?
    var lastReport = -1.0
    pump(output, input, on: videoQueue, group) { sample in
      let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
      if let gap = minGap, let last = lastKept, pts - last < gap { return false }
      lastKept = pts
      let progress = min(max((pts - timeRange.start.seconds) / duration, 0), 0.99)
      if progress - lastReport >= 0.01 {
        lastReport = progress
        self.onProgress(progress)
      }
      return true
    }
  }

  /// Copies samples until the reader runs out. [keep] can skip a sample.
  private func pump(
    _ output: AVAssetReaderTrackOutput, _ input: AVAssetWriterInput,
    on queue: DispatchQueue, _ group: DispatchGroup,
    keep: ((CMSampleBuffer) -> Bool)? = nil
  ) {
    group.enter()
    var done = false
    input.requestMediaDataWhenReady(on: queue) {
      if done { return }
      while input.isReadyForMoreMediaData {
        guard !self.isCancelled, let sample = output.copyNextSampleBuffer() else {
          done = true
          input.markAsFinished()
          group.leave()
          return
        }
        if let keep = keep, !keep(sample) { continue }
        if !input.append(sample) {
          done = true
          group.leave()
          return
        }
      }
    }
  }

  private func failure(_ error: Error?, _ message: String) -> PigeonError {
    let code: String
    switch (error as? AVError)?.code {
    case .decoderNotFound?, .encoderNotFound?, .fileFormatNotRecognized?, .decoderTemporarilyUnavailable?,
      .encoderTemporarilyUnavailable?, .invalidSourceMedia?, .operationNotSupportedForAsset?:
      code = "unsupported"
    case .noDataCaptured?, .fileFailedToParse?:
      code = "unsupported"
    default:
      code = "failed"
    }
    return PigeonError(code: code, message: "\(message): \(error?.localizedDescription ?? "unknown")", details: nil)
  }

  private func fail(_ error: Error) {
    try? FileManager.default.removeItem(at: output)
    finish(.failure(error))
  }

  private func finish(_ result: Result<Void, Error>) {
    lock.lock()
    if finished {
      lock.unlock()
      return
    }
    finished = true
    lock.unlock()
    onDone(result)
  }
}
