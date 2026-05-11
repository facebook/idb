/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// swiftlint:disable force_cast force_unwrapping

@objc(FBSimulatorVideoRecordingCommands)
public final class FBSimulatorVideoRecordingCommands: NSObject, FBVideoRecordingCommands, FBVideoStreamCommands {

  // MARK: - Properties

  private weak var simulator: FBSimulator?
  private var video: FBSimulatorVideo?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorVideoRecordingCommands {
    return FBSimulatorVideoRecordingCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBVideoRecordingCommands (legacy FBFuture entry points)

  @objc
  public func startRecording(toFile filePath: String) -> FBFuture<any FBiOSTargetOperation> {
    fbFutureFromAsync { [self] in
      try await startRecordingAsync(toFile: filePath)
    }
  }

  @objc
  public func stopRecording() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await stopRecordingAsync()
      return NSNull()
    }
  }

  // MARK: - FBVideoStreamCommands (legacy FBFuture entry point)

  @objc
  public func createStream(with configuration: FBVideoStreamConfiguration) -> FBFuture<any FBVideoStream> {
    fbFutureFromAsync { [self] in
      try await createStreamAsync(configuration: configuration)
    }
  }

  // MARK: - Private

  fileprivate func startRecordingAsync(toFile filePath: String) async throws -> any FBiOSTargetOperation {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    if video != nil {
      throw FBSimulatorError.describe("Cannot create a new video recording session, one is already active").build()
    }
    let video = FBSimulatorVideo.video(withSimctlExecutor: simulator.simctlExecutor, filePath: filePath, logger: simulator.logger!)
    try await bridgeFBFutureVoid(video.startRecording())
    self.video = video
    return video
  }

  fileprivate func stopRecordingAsync() async throws {
    let video = self.video
    self.video = nil
    guard let video else {
      throw
        FBSimulatorError
        .describe("There was no existing video instance for \(self.simulator?.description ?? "unknown")")
        .build()
    }
    try await bridgeFBFutureVoid(video.stopRecording())
  }

  fileprivate func createStreamAsync(configuration: FBVideoStreamConfiguration) async throws -> any FBVideoStream {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }
    let logger = simulator.logger
    let framebuffer = try await bridgeFBFuture(simulator.connectToFramebuffer()) as! FBFramebuffer
    return FBSimulatorVideoStream(framebuffer: framebuffer, configuration: configuration, logger: logger!) as! any FBVideoStream
  }
}

// MARK: - AsyncVideoRecordingCommands

extension FBSimulatorVideoRecordingCommands: AsyncVideoRecordingCommands {

  public func startRecording(toFile filePath: String) async throws -> any FBiOSTargetOperation {
    try await startRecordingAsync(toFile: filePath)
  }

  public func stopRecording() async throws {
    try await stopRecordingAsync()
  }
}

// MARK: - AsyncVideoStreamCommands

extension FBSimulatorVideoRecordingCommands: AsyncVideoStreamCommands {

  public func createStream(configuration: FBVideoStreamConfiguration) async throws -> any FBVideoStream {
    try await createStreamAsync(configuration: configuration)
  }
}

// MARK: - FBSimulator+AsyncVideoRecordingCommands

extension FBSimulator: AsyncVideoRecordingCommands {

  public func startRecording(toFile filePath: String) async throws -> any FBiOSTargetOperation {
    try await videoRecordingCommands().startRecording(toFile: filePath)
  }

  public func stopRecording() async throws {
    try await videoRecordingCommands().stopRecording()
  }
}

// MARK: - FBSimulator+AsyncVideoStreamCommands

extension FBSimulator: AsyncVideoStreamCommands {

  public func createStream(configuration: FBVideoStreamConfiguration) async throws -> any FBVideoStream {
    try await videoRecordingCommands().createStream(configuration: configuration)
  }
}
