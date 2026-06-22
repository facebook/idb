/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// The simctl process APIs vend Objective-C lightweight generics that erase to `id` at the Swift
// boundary, so the calls into them require force casts; the in-memory stdout is likewise force
// unwrapped. These are unavoidable at the FBControlCore process boundary.
// swiftlint:disable force_cast force_unwrapping

// MARK: - FBSimulatorVideoError

/// Errors raised by the `simctl`-backed video recorder.
///
/// Previously these were stringly-typed `FBSimulatorError` `NSError`s. No consumer inspects their
/// domain or code — they are surfaced only as messages — so they are modelled here as a typed enum.
/// `errorDescription` reproduces the original message strings verbatim, so the message is unchanged
/// when the error is bridged back to `NSError` and surfaced through `FBFuture`/`localizedDescription`.
public enum FBSimulatorVideoError: Error, LocalizedError {
  case alreadyRecording
  case noRecordingTask
  case fileNotWritten(filePath: String, timeout: TimeInterval)

  public var errorDescription: String? {
    switch self {
    case .alreadyRecording:
      return "Cannot Start Recording, there is already an recording task running"
    case .noRecordingTask:
      return "Cannot Stop Recording, there is no recording task started"
    case let .fileNotWritten(filePath, timeout):
      return "Timed out after \(timeout)s waiting for simctl to write file to \(filePath)"
    }
  }
}

extension FBSimulatorVideoError: CustomStringConvertible {
  public var description: String { errorDescription ?? "Unknown FBSimulatorVideo error" }
}

// MARK: - FBSimulatorVideo

@objc(FBSimulatorVideo)
public class FBSimulatorVideo: NSObject, FBiOSTargetOperation {

  // MARK: - Properties

  let filePath: String
  let logger: any FBControlCoreLogger
  let queue: DispatchQueue
  let completedFuture: FBMutableFuture<NSNull>

  // MARK: - Initializers

  public class func video(withSimctlExecutor simctlExecutor: FBAppleSimctlCommandExecutor, filePath: String, logger: any FBControlCoreLogger) -> FBSimulatorVideo {
    FBSimulatorVideoSimCtl(simctlExecutor: simctlExecutor, filePath: filePath, logger: logger)
  }

  /// Records simulator video in-process: drives the framebuffer through the shared
  /// `FBSimulatorVideoStream` encode pipeline and muxes the encoded frames into an `.mp4` at `filePath`
  /// via `AVAssetWriter`.
  public class func video(withFramebuffer framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, filePath: String, logger: any FBControlCoreLogger) -> FBSimulatorVideo {
    FBSimulatorVideoStreamRecorder(framebuffer: framebuffer, configuration: configuration, filePath: filePath, logger: logger)
  }

  init(filePath: String, logger: any FBControlCoreLogger) {
    self.filePath = filePath
    self.logger = logger
    self.queue = DispatchQueue(label: "com.facebook.simulatorvideo.simctl")
    self.completedFuture = FBMutableFuture<NSNull>()
    super.init()
  }

  // MARK: - Recording

  public func startRecording() async throws {
    fatalError("-[\(type(of: self)) startRecording] is abstract and should be overridden")
  }

  public func stopRecording() async throws {
    fatalError("-[\(type(of: self)) stopRecording] is abstract and should be overridden")
  }

  // MARK: - FBiOSTargetOperation

  @objc public var completed: FBFuture<NSNull> {
    convertFBMutableFuture(completedFuture).onQueue(
      queue,
      respondToCancellation: { [weak self] in
        guard let self else {
          return FBFuture<NSNull>.empty()
        }
        return fbFutureFromAsync {
          try await self.stopRecording()
          return NSNull()
        }
      })
  }
}

// MARK: - FBSimulatorVideoSimCtl

private final class FBSimulatorVideoSimCtl: FBSimulatorVideo {

  private static let recordingTaskWaitTimeout: TimeInterval = 10.0
  private static let simctlResolveFileTimeout: TimeInterval = 10.0

  private let simctlExecutor: FBAppleSimctlCommandExecutor
  private var recordingTask: FBSubprocess<NSNull, AnyObject, AnyObject>?

  init(simctlExecutor: FBAppleSimctlCommandExecutor, filePath: String, logger: any FBControlCoreLogger) {
    self.simctlExecutor = simctlExecutor
    super.init(filePath: filePath, logger: logger)
  }

  // MARK: - Recording

  override func startRecording() async throws {
    if recordingTask != nil {
      throw FBSimulatorVideoError.alreadyRecording
    }

    let version = await simctlVersion()
    let recordVideoParameters = FBSimulatorVideoSimCtlSupport.recordVideoArguments(forSimctlVersion: version)
    let ioCommandArguments = [["recordVideo"], recordVideoParameters, [filePath]].flatMap { $0 }

    let startFuture =
      (simctlExecutor.taskBuilder(withCommand: "io", arguments: ioCommandArguments) as! FBProcessBuilder<NSNull, AnyObject, AnyObject>)
      .withStdOut(to: logger)
      .withStdErr(to: logger)
      .withTaskLifecycleLogging(to: logger)
      .start() as! FBFuture<FBSubprocess<NSNull, AnyObject, AnyObject>>
    recordingTask = try await bridgeFBFuture(startFuture)
  }

  override func stopRecording() async throws {
    guard let recordingTask = self.recordingTask else {
      throw FBSimulatorVideoError.noRecordingTask
    }

    if recordingTask.statLoc.hasCompleted {
      logger.log("Stop Recording requested, but it's completed with output '\(recordingTask.stdOut!)' '\(recordingTask.stdErr!)', perhaps the video is damaged")
      return
    }

    // Mirror the previous FBFuture chain's error handling: any failure terminating the task or
    // confirming the file is logged and swallowed, and the operation still completes.
    do {
      let signalFuture =
        recordingTask
        .sendSignal(SIGINT, backingOffToKillWithTimeout: Self.recordingTaskWaitTimeout, logger: logger) as! FBFuture<AnyObject>
      try await bridgeFBFutureVoid(signalFuture.logCompletion(logger, withPurpose: "The video recording task terminated"))
      self.recordingTask = nil
      try await confirmFileHasBeenWritten()
    } catch {
      logger.log("Failed confirm video file been written \(error)")
    }

    completedFuture.resolve(withResult: NSNull())
  }

  // MARK: - Private

  private func confirmFileHasBeenWritten() async throws {
    let deadline = Date().addingTimeInterval(Self.simctlResolveFileTimeout)
    while true {
      let fileAttributes = try? FileManager.default.attributesOfItem(atPath: filePath)
      let fileSize = (fileAttributes?[.size] as? UInt) ?? 0
      if fileSize > 0 {
        logger.log("simctl has written out the video to \(filePath) with file size \(fileSize)")
        return
      }
      if Date() >= deadline {
        throw FBSimulatorVideoError.fileNotWritten(filePath: filePath, timeout: Self.simctlResolveFileTimeout)
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    }
  }

  private func simctlVersion() async -> NSDecimalNumber {
    do {
      let builder =
        (((FBProcessBuilder<NSNull, AnyObject, AnyObject>
          .withLaunchPath("/usr/bin/what", arguments: ["/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl"]) as! FBProcessBuilder<NSNull, AnyObject, AnyObject>)
          .withStdOutInMemoryAsString() as! FBProcessBuilder<NSNull, AnyObject, AnyObject>)
          .withStdErrToDevNull() as! FBProcessBuilder<NSNull, AnyObject, AnyObject>)
      let task = try await bridgeFBFuture(builder.runUntilCompletion(withAcceptableExitCodes: nil))
      let subprocess = task as! FBSubprocess<NSNull, NSString, NSNull>
      let output = subprocess.stdOut! as String
      guard let version = FBSimulatorVideoSimCtlSupport.parseSimctlVersion(fromWhatOutput: output) else {
        logger.log("Couldn't find simctl version from: \(output), return 0.0")
        return .zero
      }
      return version
    } catch {
      logger.log("Abnormal exit of 'what' process \(error), assuming version 0.0")
      return .zero
    }
  }
}

// MARK: - FBSimulatorVideoSimCtlSupport

/// Pure helpers for the `simctl`-backed recorder, factored out of `FBSimulatorVideoSimCtl` so the
/// version gating and version parsing can be exercised by unit tests without a running simulator.
enum FBSimulatorVideoSimCtlSupport {

  /// CoreSimulator 681.14 is the first version whose `simctl io recordVideo` accepts `--codec`/`--force`.
  /// Earlier versions take `--type` instead.
  static let codecArgumentsMinimumVersion = NSDecimalNumber(string: "681.14")

  /// The `simctl io recordVideo` codec arguments appropriate for the given CoreSimulator version.
  static func recordVideoArguments(forSimctlVersion version: NSDecimalNumber) -> [String] {
    if version.compare(codecArgumentsMinimumVersion) != .orderedAscending {
      return ["--codec=h264", "--force"]
    }
    return ["--type=mp4"]
  }

  /// Parses the CoreSimulator version out of `/usr/bin/what` output (e.g. a line containing
  /// `CoreSimulator-681.14`). Returns `nil` when no version can be found.
  static func parseSimctlVersion(fromWhatOutput output: String) -> NSDecimalNumber? {
    let pattern = "CoreSimulator-([0-9\\.]+)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
      return nil
    }
    let matches = regex.matches(in: output, options: [], range: NSRange(location: 0, length: output.count))
    guard let match = matches.first else {
      return nil
    }
    return NSDecimalNumber(string: (output as NSString).substring(with: match.range(at: 1)))
  }
}

// MARK: - FBSimulatorVideoStreamRecorder

/// Records simulator video in-process. Reuses `FBSimulatorVideoStream` to attach to the framebuffer,
/// drive an eager (constant-frame-rate) cadence, and encode via VideoToolbox — but routes the encoded
/// frames into an `FBVideoFileWriter` (`AVAssetWriter`) rather than byte-framing them to a data
/// consumer. The byte-stream consumer is a discard; only the `.mp4` is produced.
private final class FBSimulatorVideoStreamRecorder: FBSimulatorVideo {
  private let stream: FBSimulatorVideoStream
  private let fileWriter: FBVideoFileWriter
  private var hasStopped = false

  init(framebuffer: FBFramebuffer, configuration: FBVideoStreamConfiguration, filePath: String, logger: any FBControlCoreLogger) {
    let fileWriter = FBVideoFileWriter(filePath: filePath, logger: logger)
    self.fileWriter = fileWriter
    self.stream = FBSimulatorVideoStream.makeRecorder(framebuffer: framebuffer, configuration: configuration, fileWriter: fileWriter, logger: logger)
    super.init(filePath: filePath, logger: logger)
  }

  override func startRecording() async throws {
    // Encoded frames are routed to `fileWriter` (which opens lazily on its first sample, since
    // passthrough muxing needs that sample's format); the stream's byte consumer is unused, so a
    // no-op consumer satisfies its streaming bookkeeping (and never reports back-pressure).
    try await bridgeFBFutureVoid(stream.startStreaming(FBNullDataConsumer()))
  }

  override func stopRecording() async throws {
    if hasStopped {
      return
    }
    hasStopped = true
    // Stop the framebuffer push and flush the encoder (tearDown's VTCompressionSessionCompleteFrames
    // drains all pending frames into `fileWriter`) before finalizing the file's moov.
    try await bridgeFBFutureVoid(stream.stopStreaming())
    try await fileWriter.finish()
    completedFuture.resolve(withResult: NSNull())
  }
}
