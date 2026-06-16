/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// MARK: - FBSimulatorVideo

@objc(FBSimulatorVideo)
public class FBSimulatorVideo: NSObject, FBiOSTargetOperation {

  // MARK: - Properties

  let filePath: String
  let logger: any FBControlCoreLogger
  let queue: DispatchQueue
  let completedFuture: FBMutableFuture<NSNull>

  // MARK: - Initializers

  @objc(videoWithSimctlExecutor:filePath:logger:)
  public class func video(withSimctlExecutor simctlExecutor: FBAppleSimctlCommandExecutor, filePath: String, logger: any FBControlCoreLogger) -> FBSimulatorVideo {
    FBSimulatorVideoSimCtl(simctlExecutor: simctlExecutor, filePath: filePath, logger: logger)
  }

  init(filePath: String, logger: any FBControlCoreLogger) {
    self.filePath = filePath
    self.logger = logger
    self.queue = DispatchQueue(label: "com.facebook.simulatorvideo.simctl")
    self.completedFuture = FBMutableFuture<NSNull>()
    super.init()
  }

  // MARK: - Public Methods

  @objc
  public func startRecording() -> FBFuture<NSNull> {
    fatalError("-[\(type(of: self)) startRecording] is abstract and should be overridden")
  }

  @objc
  public func stopRecording() -> FBFuture<NSNull> {
    fatalError("-[\(type(of: self)) stopRecording] is abstract and should be overridden")
  }

  // MARK: - FBiOSTargetOperation

  @objc
  public var completed: FBFuture<NSNull> {
    unsafeBitCast(
      completedFuture.onQueue(
        queue,
        respondToCancellation: { [weak self] in
          guard let self else {
            return FBFuture<NSNull>.empty()
          }
          return self.stopRecording()
        }),
      to: FBFuture<NSNull>.self
    )
  }
}

// MARK: - FBSimulatorVideoSimCtl

private class FBSimulatorVideoSimCtl: FBSimulatorVideo {

  private let simctlExecutor: FBAppleSimctlCommandExecutor
  private var recordingStarted: FBFuture<FBSubprocess<NSNull, AnyObject, AnyObject>>?

  init(simctlExecutor: FBAppleSimctlCommandExecutor, filePath: String, logger: any FBControlCoreLogger) {
    self.simctlExecutor = simctlExecutor
    super.init(filePath: filePath, logger: logger)
  }

  // MARK: - Public

  override func startRecording() -> FBFuture<NSNull> {
    if recordingStarted != nil {
      return
        FBSimulatorError
        .describe("Cannot Start Recording, there is already an recording task running")
        .failFuture() as! FBFuture<NSNull>
    }

    let started: FBFuture<FBSubprocess<NSNull, AnyObject, AnyObject>> =
      (simctlVersionNumber()
      .onQueue(
        queue,
        fmap: { [weak self] (simctlVersion: Any) -> FBFuture<AnyObject> in
          guard let self else {
            return FBFuture(error: FBSimulatorError.describe("Deallocated").build())
          }
          let version = simctlVersion as! NSDecimalNumber
          let recordVideoParameters = FBSimulatorVideoSimCtlSupport.recordVideoArguments(forSimctlVersion: version)

          let ioCommandArguments = [["recordVideo"], recordVideoParameters, [self.filePath]].flatMap { $0 }

          return
            ((self.simctlExecutor
            .taskBuilder(withCommand: "io", arguments: ioCommandArguments) as! FBProcessBuilder<NSNull, AnyObject, AnyObject>)
            .withStdOut(to: self.logger)
            .withStdErr(to: self.logger)
            .withTaskLifecycleLogging(to: self.logger)
            .start()) as! FBFuture<AnyObject>
        })) as! FBFuture<FBSubprocess<NSNull, AnyObject, AnyObject>>

    recordingStarted = started
    return started.mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  private static let recordingTaskWaitTimeout: TimeInterval = 10.0

  override func stopRecording() -> FBFuture<NSNull> {
    guard let recordingStarted = self.recordingStarted else {
      return
        FBSimulatorError
        .describe("Cannot Stop Recording, there is no recording task started")
        .failFuture() as! FBFuture<NSNull>
    }
    guard let recordingTask = recordingStarted.result else {
      return
        FBSimulatorError
        .describe("Cannot Stop Recording, the recording task hasn't started")
        .failFuture() as! FBFuture<NSNull>
    }

    if recordingTask.statLoc.hasCompleted {
      logger.log("Stop Recording requested, but it's completed with output '\(recordingTask.stdOut!)' '\(recordingTask.stdErr!)', perhaps the video is damaged")
      return FBFuture<NSNull>.empty()
    }

    let completed: FBFuture<NSNull> =
      (((recordingTask
      .sendSignal(SIGINT, backingOffToKillWithTimeout: FBSimulatorVideoSimCtl.recordingTaskWaitTimeout, logger: logger) as! FBFuture<AnyObject>)
      .logCompletion(logger, withPurpose: "The video recording task terminated"))
      .onQueue(
        queue,
        fmap: { [weak self] (_: Any) -> FBFuture<AnyObject> in
          guard let self else {
            return FBFuture(result: NSNull())
          }
          self.recordingStarted = nil
          return FBSimulatorVideoSimCtl.confirmFileHasBeenWritten(self.filePath, queue: self.queue, logger: self.logger) as! FBFuture<AnyObject>
        }
      )
      .onQueue(
        queue,
        handleError: { [weak self] (error: any Error) -> FBFuture<AnyObject> in
          self?.logger.log("Failed confirm video file been written \(error)")
          return FBFuture(result: NSNull())
        })) as! FBFuture<NSNull>

    _ = completedFuture.resolve(from: unsafeBitCast(completed, to: FBFuture<AnyObject>.self))

    return completed
  }

  // MARK: - Private

  private static let simctlResolveFileTimeout: TimeInterval = 10

  private class func confirmFileHasBeenWritten(_ filePath: String, queue: DispatchQueue, logger: any FBControlCoreLogger) -> FBFuture<NSNull> {
    (FBFuture<AnyObject>
      .onQueue(
        queue,
        resolveWhen: {
          let fileAttributes = try? FileManager.default.attributesOfItem(atPath: filePath)
          let fileSize = (fileAttributes?[.size] as? UInt) ?? 0
          if fileSize > 0 {
            logger.log("simctl has written out the video to \(filePath) with file size \(fileSize)")
            return true
          }
          return false
        }
      )
      .timeout(simctlResolveFileTimeout, waitingFor: "simctl to write file to \(filePath)")) as! FBFuture<NSNull>
  }

  private func simctlVersionNumber() -> FBFuture<AnyObject> {
    ((((FBProcessBuilder<NSNull, AnyObject, AnyObject>
      .withLaunchPath("/usr/bin/what", arguments: ["/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl"]) as! FBProcessBuilder<NSNull, AnyObject, AnyObject>)
      .withStdOutInMemoryAsString() as! FBProcessBuilder<NSNull, AnyObject, AnyObject>)
      .withStdErrToDevNull() as! FBProcessBuilder<NSNull, AnyObject, AnyObject>)
      .runUntilCompletion(withAcceptableExitCodes: nil)
      .onQueue(
        queue,
        fmap: { [weak self] (task: Any) -> FBFuture<AnyObject> in
          let subprocess = task as! FBSubprocess<NSNull, NSString, NSNull>
          let output = subprocess.stdOut! as String
          guard let version = FBSimulatorVideoSimCtlSupport.parseSimctlVersion(fromWhatOutput: output) else {
            self?.logger.log("Couldn't find simctl version from: \(output), return 0.0")
            return FBFuture(result: NSDecimalNumber.zero)
          }
          return FBFuture(result: version)
        }
      )
      .onQueue(
        queue,
        handleError: { [weak self] (error: any Error) -> FBFuture<AnyObject> in
          self?.logger.log("Abnormal exit of 'what' process \(error), assuming version 0.0")
          return FBFuture(result: NSDecimalNumber.zero)
        }))
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
