// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation
@preconcurrency import FBControlCore
import Foundation

@objc(FBDeviceVideoRecordingCommands)
public class FBDeviceVideoRecordingCommands: NSObject, FBVideoRecordingCommands, FBVideoStreamCommands {
  private weak var device: FBDevice?
  private var video: FBDeviceVideo?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBVideoRecordingCommands

  public func startRecording(toFile filePath: String) -> FBFuture<any FBiOSTargetOperation> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    if video != nil {
      return FBDeviceControlError().describe("Cannot create a new video recording session, one is already active").failFuture() as! FBFuture<any FBiOSTargetOperation>
    }
    return
      (FBDeviceVideo.video(for: device, filePath: filePath)
      .onQueue(
        device.workQueue,
        fmap: { video -> FBFuture<AnyObject> in
          self.video = video
          return video.startRecording().mapReplace(video as AnyObject)
        })) as! FBFuture<any FBiOSTargetOperation>
  }

  public func stopRecording() -> FBFuture<NSNull> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    guard let video else {
      return FBDeviceControlError().describe("There was no existing video instance for \(device)").failFuture() as! FBFuture<NSNull>
    }
    self.video = nil
    return video.stopRecording()
  }

  // MARK: - FBVideoStreamCommands

  public func createStream(with configuration: FBVideoStreamConfiguration) -> FBFuture<any FBVideoStream> {
    guard let device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (FBDeviceVideo.captureSession(for: device)
      .onQueue(
        device.workQueue,
        fmap: { session -> FBFuture<AnyObject> in
          do {
            let logger = device.logger ?? FBControlCoreGlobalConfiguration.defaultLogger
            let stream = try FBDeviceVideoStream.stream(withSession: session, configuration: configuration, logger: logger)
            return FBFuture(result: stream as AnyObject)
          } catch {
            return FBFuture(error: error)
          }
        })) as! FBFuture<any FBVideoStream>
  }
}
