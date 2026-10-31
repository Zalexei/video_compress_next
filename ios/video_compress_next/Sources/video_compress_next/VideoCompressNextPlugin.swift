// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import Flutter
import UIKit

public class VideoCompressNextPlugin: NSObject, FlutterPlugin, VideoCompressHostApi {
  private let flutterApi: VideoCompressFlutterApi
  /// Touched on the main thread only.
  private var jobs: [String: CompressJob] = [:]
  private let background = DispatchQueue(
    label: "video_compress_next.io", qos: .userInitiated, attributes: .concurrent)

  init(flutterApi: VideoCompressFlutterApi) {
    self.flutterApi = flutterApi
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger()
    let instance = VideoCompressNextPlugin(flutterApi: VideoCompressFlutterApi(binaryMessenger: messenger))
    VideoCompressHostApiSetup.setUp(binaryMessenger: messenger, api: instance)
    registrar.publish(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    VideoCompressHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: nil)
    jobs.values.forEach { $0.cancel() }
  }

  func getMediaInfo(path: String, completion: @escaping (Result<NativeMediaInfo, Error>) -> Void) {
    inBackground(completion) { try MediaInfoReader.read(path) }
  }

  func compress(request: NativeCompressRequest, completion: @escaping (Result<Void, Error>) -> Void) {
    let taskId = request.taskId
    if jobs[taskId] != nil {
      completion(.failure(PigeonError(code: "failed", message: "Task \(taskId) is already running", details: nil)))
      return
    }
    // AVAssetWriter fails as soon as the app is in the background, unless a
    // background task keeps it running; iOS grants only a short while.
    var backgroundTask = UIBackgroundTaskIdentifier.invalid
    let job = CompressJob(
      request: request,
      onProgress: { [weak self] progress in
        DispatchQueue.main.async {
          self?.flutterApi.onProgress(taskId: taskId, progress: progress) { _ in }
        }
      },
      onDone: { [weak self] result in
        DispatchQueue.main.async {
          self?.jobs[taskId] = nil
          if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
          }
          completion(result)
        }
      })
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "video_compress_next") {
      job.stop(
        PigeonError(
          code: "failed", message: "The app stayed in the background too long to finish the compression",
          details: nil))
      // iOS ends the app if the task is still open when this handler returns.
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
    jobs[taskId] = job
    job.start()
  }

  func cancel(taskId: String) throws {
    jobs[taskId]?.cancel()
  }

  func getThumbnail(
    request: NativeThumbnailRequest,
    completion: @escaping (Result<FlutterStandardTypedData, Error>) -> Void
  ) {
    inBackground(completion) { FlutterStandardTypedData(bytes: try Thumbnails.jpeg(request)) }
  }

  func cacheDirectory() throws -> String {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let dir = caches.appendingPathComponent("video_compress_next", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.path
  }

  /// Replies go back on the main thread, where the engine expects them.
  private func inBackground<T>(
    _ completion: @escaping (Result<T, Error>) -> Void, _ work: @escaping () throws -> T
  ) {
    background.async {
      // Errors that are not PigeonError would reach Dart with their
      // description as the code and the type name as the message.
      let result = Result { try work() }.mapError { error -> Error in
        error as? PigeonError
          ?? PigeonError(code: "failed", message: error.localizedDescription, details: nil)
      }
      DispatchQueue.main.async { completion(result) }
    }
  }
}
