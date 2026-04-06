// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import AVFoundation
import CoreMediaIO
@preconcurrency import FBControlCore
import Foundation

@objc(FBDeviceVideo)
public class FBDeviceVideo: NSObject, FBiOSTargetOperation {
  private let encoder: FBVideoFileWriter
  private let workQueue: DispatchQueue

  // MARK: Initialization Helpers

  private class func findCaptureDevice(for device: FBDevice) -> FBFuture<AVCaptureDevice> {
    return unsafeBitCast(
      FBFuture<AnyObject>.onQueue(device.workQueue, resolveUntil: {
        guard let captureDevice = AVCaptureDevice(uniqueID: device.udid) else {
          return FBDeviceControlError.describe("Capture Device \(device.udid) not available").failFuture()
        }
        return FBFuture(result: captureDevice as AnyObject)
      }).timeout(FBControlCoreGlobalConfiguration.fastTimeout, waitingFor: "Device \(device) to have an associated capture device appear"),
      to: FBFuture<AVCaptureDevice>.self
    )
  }

  private class func allowAccessToScreenCaptureDevices() throws {
    var properties = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var allow: UInt32 = 1
    let status = CMIOObjectSetPropertyData(
      CMIOObjectID(kCMIOObjectSystemObject),
      &properties,
      0,
      nil,
      UInt32(MemoryLayout<UInt32>.size),
      &allow
    )
    if status != 0 {
      throw FBDeviceControlError.describe("Failed to enable Screen Capture devices with status \(status)").build()
    }
  }

  // MARK: Initializers

  @objc(captureSessionForDevice:)
  public class func captureSession(for device: FBDevice) -> FBFuture<AVCaptureSession> {
    do {
      try allowAccessToScreenCaptureDevices()
    } catch {
      return FBFuture(error: error)
    }
    return unsafeBitCast(
      findCaptureDevice(for: device).onQueue(device.workQueue, fmap: { (d: AnyObject) -> FBFuture<AnyObject> in
        let captureDevice = d as! AVCaptureDevice
        let deviceInput: AVCaptureDeviceInput
        do {
          deviceInput = try AVCaptureDeviceInput(device: captureDevice)
        } catch {
          return FBFuture(error: error)
        }
        let session = AVCaptureSession()
        if !session.canAddInput(deviceInput) {
          return FBDeviceControlError.describe("Cannot add Device Input to session for \(captureDevice)").failFuture()
        }
        session.addInput(deviceInput)
        return FBFuture(result: session as AnyObject)
      }),
      to: FBFuture<AVCaptureSession>.self
    )
  }

  @objc(videoForDevice:filePath:)
  public class func video(for device: FBDevice, filePath: String) -> FBFuture<FBDeviceVideo> {
    return unsafeBitCast(
      captureSession(for: device).onQueue(device.workQueue, fmap: { (s: AnyObject) -> FBFuture<AnyObject> in
        let session = s as! AVCaptureSession
        let encoder: FBVideoFileWriter
        do {
          encoder = try FBVideoFileWriter.writer(withSession: session, filePath: filePath, logger: device.logger ?? FBControlCoreGlobalConfiguration.defaultLogger)
        } catch {
          return FBFuture(error: error)
        }
        let video = FBDeviceVideo(encoder: encoder, workQueue: device.workQueue)
        return FBFuture(result: video as AnyObject)
      }),
      to: FBFuture<FBDeviceVideo>.self
    )
  }

  private init(encoder: FBVideoFileWriter, workQueue: DispatchQueue) {
    self.encoder = encoder
    self.workQueue = workQueue
    super.init()
  }

  // MARK: Public

  @objc public func startRecording() -> FBFuture<NSNull> {
    return encoder.startRecording()
  }

  @objc public func stopRecording() -> FBFuture<NSNull> {
    return encoder.stopRecording()
  }

  // MARK: FBiOSTargetOperation

  @objc public var completed: FBFuture<NSNull> {
    let encoder = self.encoder
    return encoder.completed().onQueue(workQueue, respondToCancellation: {
      return encoder.stopRecording()
    })
  }
}
