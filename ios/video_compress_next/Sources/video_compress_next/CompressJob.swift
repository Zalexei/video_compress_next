// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import AVFoundation

/// One compression with AVAssetReader and AVAssetWriter, which, unlike
/// AVAssetExportSession presets, take an exact size, bitrate and codec.
///
/// Reader and writer are only touched on `queue` and the pump queues, in the
/// states AVFoundation allows: calling cancelReading or cancelWriting from
/// another thread while they start or finish raises an Objective-C exception.
/// [stop] therefore only records the reason; the pipeline notices it, tears
/// down what it started and then reports.
final class CompressJob {
  private let request: NativeCompressRequest
  private let onProgress: (Double) -> Void
  private let onDone: (Result<Void, Error>) -> Void
  private let output: URL
  private let queue = DispatchQueue(label: "video_compress_next.job", qos: .userInitiated)
  private let videoQueue = DispatchQueue(label: "video_compress_next.video", qos: .userInitiated)
  private let audioQueue = DispatchQueue(label: "video_compress_next.audio", qos: .userInitiated)
  private let lock = NSLock()
  private var stopReason: PigeonError?
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

  /// Asks the job to stop; it reports [reason] once reader and writer are down.
  func stop(_ reason: PigeonError) {
    lock.lock()
    if stopReason == nil && !finished { stopReason = reason }
    lock.unlock()
  }

  func cancel() {
    stop(PigeonError(code: "cancelled", message: "The compression was cancelled.", details: nil))
  }

  private var stopped: PigeonError? {
    lock.lock()
    defer { lock.unlock() }
    return stopReason
  }

  private func run() throws {
    if let reason = stopped { return fail(reason) }
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
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings(videoTrack))
    // Frames are encoded as stored and the rotation is kept as metadata.
    videoInput.transform = videoTrack.preferredTransform
    videoInput.expectsMediaDataInRealTime = false
    writer.add(videoInput)

    var audio: (AVAssetReaderTrackOutput, AVAssetWriterInput)?
    if request.includeAudio, let audioTrack = asset.tracks(withMediaType: .audio).first {
      audio = try addAudio(audioTrack, reader, writer)
    }

    if let reason = stopped { return fail(reason) }
    guard reader.startReading() else { throw failure(reader.error, "Cannot read the video") }
    guard writer.startWriting() else {
      reader.cancelReading()
      throw failure(writer.error, "Cannot write the video")
    }
    writer.startSession(atSourceTime: timeRange.start)

    let group = DispatchGroup()
    pumpVideo(videoOutput, videoInput, timeRange, group)
    if let (audioOutput, audioInput) = audio {
      pump(audioOutput, audioInput, on: audioQueue, group)
    }
    // Both pumps have returned, so nothing appends or reads any more and
    // reader and writer can be cancelled or finished safely.
    group.notify(queue: queue) {
      if let reason = self.stopped {
        if reader.status == .reading { reader.cancelReading() }
        if writer.status == .writing { writer.cancelWriting() }
        return self.fail(reason)
      }
      if reader.status == .failed || writer.status != .writing {
        if reader.status == .reading { reader.cancelReading() }
        if writer.status == .writing { writer.cancelWriting() }
        let error = reader.status == .failed ? reader.error : writer.error
        return self.fail(self.failure(error, "Compressing the video failed"))
      }
      writer.finishWriting {
        self.queue.async {
          if let reason = self.stopped { return self.fail(reason) }
          if writer.status == .completed {
            self.onProgress(1)
            self.finish(.success(()))
          } else {
            self.fail(self.failure(writer.error, "Writing the video failed"))
          }
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

  /// Whether the device can encode HEVC. AVAssetWriter.canApply only checks
  /// the settings' syntax, so it says yes on devices without an encoder.
  private static let canEncodeHevc =
    AVAssetExportSession.allExportPresets().contains(AVAssetExportPresetHEVCHighestQuality)

  private func videoSettings(_ track: AVAssetTrack) -> [String: Any] {
    let sideways = Sources.rotation(track.preferredTransform) % 180 != 0
    var width = Int(track.naturalSize.width.rounded())
    var height = Int(track.naturalSize.height.rounded())
    // The requested size is as displayed; the encoder gets frames as stored.
    if let w = request.width, let h = request.height {
      width = Int(sideways ? h : w)
      height = Int(sideways ? w : h)
    }
    let hevc = request.codec == .hevc && CompressJob.canEncodeHevc
    let bitrate = request.codec == .hevc && !hevc
      ? request.fallbackVideoBitrate ?? request.videoBitrate : request.videoBitrate
    var compression: [String: Any] = [AVVideoMaxKeyFrameIntervalDurationKey: 2]
    if let bitrate = bitrate { compression[AVVideoAverageBitRateKey] = bitrate }
    if let fps = request.maxFrameRate { compression[AVVideoExpectedSourceFrameRateKey] = fps }
    return [
      AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
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
  }

  private func addAudio(
    _ track: AVAssetTrack, _ reader: AVAssetReader, _ writer: AVAssetWriter
  ) throws -> (AVAssetReaderTrackOutput, AVAssetWriterInput) {
    var sourceRate = 44_100.0
    var channels: UInt32 = 2
    if let description = track.formatDescriptions.first,
      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(
        description as! CMAudioFormatDescription)?.pointee
    {
      if asbd.mSampleRate > 0 { sourceRate = asbd.mSampleRate }
      if asbd.mChannelsPerFrame > 0 { channels = min(asbd.mChannelsPerFrame, 2) }
    }
    // The AAC encoder rejects 64 and 128 kbps at low sample rates (voice
    // recordings at 8 to 16 kHz), so the reader resamples to 44.1 or 48 kHz.
    let sampleRate = sourceRate >= 48_000 ? 48_000.0 : 44_100.0
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
    guard reader.canAdd(output), writer.canAdd(input) else {
      throw PigeonError(
        code: "unsupported", message: "Cannot re-encode the audio track of \(request.inputPath)",
        details: nil)
    }
    reader.add(output)
    writer.add(input)
    return (output, input)
  }

  private func pumpVideo(
    _ output: AVAssetReaderTrackOutput, _ input: AVAssetWriterInput,
    _ timeRange: CMTimeRange, _ group: DispatchGroup
  ) {
    let duration = max(timeRange.duration.seconds, 0.001)
    // Frames are kept on a time grid of 1/maxFrameRate: a frame is kept when
    // it reaches the next due time. Measuring from the last kept frame
    // instead would turn 30 fps capped at 24 into 15 fps.
    let interval = request.maxFrameRate.map { 1 / Double($0) }
    var due: Double?
    var lastReport = -1.0
    pump(output, input, on: videoQueue, group) { [weak self] sample in
      let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
      if let interval = interval {
        if let next = due, pts + 0.0005 < next { return false }
        // Fall back onto the grid after a gap instead of keeping a burst.
        due = due.map { max($0 + interval, pts + interval * 0.5) } ?? pts + interval
      }
      let progress = min(max((pts - timeRange.start.seconds) / duration, 0), 0.99)
      if progress - lastReport >= 0.01 {
        lastReport = progress
        self?.onProgress(progress)
      }
      return true
    }
  }

  /// Copies samples until the reader runs out or the job stops. [keep] can
  /// skip a sample.
  private func pump(
    _ output: AVAssetReaderTrackOutput, _ input: AVAssetWriterInput,
    on queue: DispatchQueue, _ group: DispatchGroup,
    keep: ((CMSampleBuffer) -> Bool)? = nil
  ) {
    group.enter()
    var done = false
    input.requestMediaDataWhenReady(on: queue) { [weak self] in
      if done { return }
      func end() {
        done = true
        input.markAsFinished()
        group.leave()
      }
      while input.isReadyForMoreMediaData {
        guard let self = self, self.stopped == nil, let sample = output.copyNextSampleBuffer() else {
          return end()
        }
        if let keep = keep, !keep(sample) { continue }
        if !input.append(sample) { return end() }
      }
    }
  }

  private func failure(_ error: Error?, _ message: String) -> PigeonError {
    let code: String
    switch (error as? AVError)?.code {
    case .decoderNotFound?, .encoderNotFound?, .fileFormatNotRecognized?, .invalidSourceMedia?,
      .operationNotSupportedForAsset?, .fileFailedToParse?, .noDataCaptured?:
      code = "unsupported"
    default:
      // Includes temporarily unavailable codecs: worth trying again later.
      code = "failed"
    }
    return PigeonError(code: code, message: "\(message): \(error?.localizedDescription ?? "unknown")", details: nil)
  }

  /// Reports [error] after removing the partial file. Errors that are not
  /// PigeonError would reach Dart with their description as the code.
  private func fail(_ error: Error) {
    try? FileManager.default.removeItem(at: output)
    let reported = error as? PigeonError
      ?? PigeonError(code: "failed", message: error.localizedDescription, details: nil)
    finish(.failure(reported))
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
