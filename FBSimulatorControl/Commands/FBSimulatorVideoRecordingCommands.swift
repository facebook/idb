/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

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

  // MARK: - FBVideoRecordingCommands

  @objc
  public func startRecording(toFile filePath: String) -> FBFuture<any FBiOSTargetOperation> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator deallocated").build())
    }
    if video != nil {
      return
        FBSimulatorError
        .describe("Cannot create a new video recording session, one is already active")
        .failFuture() as! FBFuture<any FBiOSTargetOperation>
    }
    return
      (FBSimulatorVideoRecordingCommands.videoImplementation(for: simulator, filePath: filePath)
      .onQueue(
        simulator.workQueue,
        fmap: { [weak self] (video: Any) -> FBFuture<AnyObject> in
          let video = video as! FBSimulatorVideo
          return video.startRecording()
            .onQueue(
              simulator.workQueue,
              map: { (_: Any) -> AnyObject in
                self?.video = video
                return video
              })
        })) as! FBFuture<any FBiOSTargetOperation>
  }

  @objc
  public func stopRecording() -> FBFuture<NSNull> {
    let video = self.video
    self.video = nil
    guard let video else {
      return
        FBSimulatorError
        .describe("There was no existing video instance for \(self.simulator?.description ?? "unknown")")
        .failFuture() as! FBFuture<NSNull>
    }
    return video.stopRecording()
  }

  // MARK: - FBVideoStreamCommands

  @objc
  public func createStream(with configuration: FBVideoStreamConfiguration) -> FBFuture<any FBVideoStream> {
    guard let simulator = self.simulator else {
      return FBFuture(error: FBSimulatorError.describe("Simulator deallocated").build())
    }
    let logger = simulator.logger
    return
      (simulator.connectToFramebuffer()
      .onQueue(
        simulator.workQueue,
        map: { (framebuffer: Any) -> AnyObject in
          let framebuffer = framebuffer as! FBFramebuffer
          return FBSimulatorVideoStream(framebuffer: framebuffer, configuration: configuration, logger: logger!)
        })) as! FBFuture<any FBVideoStream>
  }

  // MARK: - Private

  private class func videoImplementation(for simulator: FBSimulator, filePath: String) -> FBFuture<AnyObject> {
    let video = FBSimulatorVideo.video(withSimctlExecutor: simulator.simctlExecutor, filePath: filePath, logger: simulator.logger!)
    return FBFuture(result: video)
  }
}
