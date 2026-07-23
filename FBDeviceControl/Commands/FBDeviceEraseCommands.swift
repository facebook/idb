/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let EraseCallbackValueGood: Int32 = -10
private let DetectTimeout: TimeInterval = 10
private let APICallbackTimeout: TimeInterval = 15
private let OfflineTimeout: TimeInterval = 20
private let OnlineTimeout: TimeInterval = 300

// MARK: - FBDeviceEraseOperation

private final class FBDeviceEraseOperation: NSObject, FBiOSTargetSetDelegate, @unchecked Sendable {

  private let udid: String
  private let calls: AMDCalls
  private let logger: any FBControlCoreLogger
  private let queue: DispatchQueue
  private let deviceManager: FBAMRestorableDeviceManager
  private let deviceDetected = FBMutableFuture<NSNull>()
  private let deviceWentAway = FBMutableFuture<NSNull>()
  private let deviceCameBack = FBMutableFuture<NSNull>()
  private let eraseCallbackResult = FBMutableFuture<NSNumber>()

  init(device: FBDevice, logger: any FBControlCoreLogger) {
    let queue = DispatchQueue(label: "com.facebook.fbdeviceerase")
    self.udid = device.udid
    self.calls = device.calls
    self.logger = logger
    self.queue = queue
    self.deviceManager = FBAMRestorableDeviceManager(
      calls: device.calls,
      work: queue,
      asyncQueue: queue,
      ecidFilter: device.uniqueIdentifier,
      logger: logger
    )
    super.init()
    self.deviceManager.delegate = self
  }

  // MARK: Erase

  func erase() async throws {
    try deviceManager.startListening()
    try await awaitEvent(deviceDetected, timeout: DetectTimeout, waitingFor: "Device to be detected the first time")
    logger.log("Device has been detected, starting erase API Call")
    let eraseCallbackValue = try await startErase()
    guard eraseCallbackValue == EraseCallbackValueGood else {
      throw FBDeviceControlError().describe("Erase callback was \(eraseCallbackValue), not \(EraseCallbackValueGood). Perhaps the device is not activated?").build()
    }
    logger.log("Device API call finished, waiting for device to go offline")
    try await awaitEvent(deviceWentAway, timeout: OfflineTimeout, waitingFor: "Device to go offline")
    logger.log("Device has gone offline, waiting for it to come back online")
    try await awaitEvent(deviceCameBack, timeout: OnlineTimeout, waitingFor: "Device to come back")
  }

  // MARK: Private

  /// Issues `AMSEraseDevice` on the serial queue and awaits the value delivered by
  /// the C erase callback (with a timeout).
  private func startErase() async throws -> Int32 {
    queue.async { [self] in
      let selfContext = Unmanaged.passUnretained(self).toOpaque()
      _ = calls.AMSInitialize?(0)
      let status =
        calls.AMSEraseDevice?(
          udid as CFString,
          { _, progress, context in
            guard let context else {
              return 0
            }
            let operation = Unmanaged<FBDeviceEraseOperation>.fromOpaque(context).takeUnretainedValue()
            operation.logger.log("Erase Callback is \(progress)")
            operation.eraseCallbackResult.resolve(withResult: NSNumber(value: progress))
            return 0
          },
          selfContext
        ) ?? -1
      logger.log("AMSEraseDevice had status \(status)")
    }
    // swiftlint:disable:next force_cast
    let timed = convertFBMutableFuture(eraseCallbackResult).timeout(APICallbackTimeout, waitingFor: "Device erase API call to resolve") as! FBFuture<NSNumber>
    let result = try await bridgeFBFuture(timed)
    return result.int32Value
  }

  private func awaitEvent(_ future: FBMutableFuture<NSNull>, timeout: TimeInterval, waitingFor description: String) async throws {
    // swiftlint:disable:next force_cast
    let timed = convertFBMutableFuture(future).timeout(timeout, waitingFor: description) as! FBFuture<NSNull>
    try await bridgeFBFutureVoid(timed)
  }

  // MARK: FBiOSTargetSetDelegate

  func targetAdded(_ targetInfo: any FBiOSTargetInfo, in targetSet: any FBiOSTargetSet) {
    if deviceDetected.state == .running {
      logger.log("Got target \(targetInfo) added for the first time")
      deviceDetected.resolve(withResult: NSNull())
    } else {
      logger.log("Got target \(targetInfo) added")
      deviceCameBack.resolve(withResult: NSNull())
    }
  }

  func targetRemoved(_ targetInfo: any FBiOSTargetInfo, in targetSet: any FBiOSTargetSet) {
    logger.log("Got target \(targetInfo) removed")
    deviceWentAway.resolve(withResult: NSNull())
  }

  func targetUpdated(_ targetInfo: any FBiOSTargetInfo, in targetSet: any FBiOSTargetSet) {}
}

// MARK: - FBDeviceEraseCommands

public final class FBDeviceEraseCommands: NSObject, FBiOSTargetCommand, EraseCommands {

  private weak var device: FBDevice?

  public class func commands(with target: any FBiOSTarget) -> Self {
    // swiftlint:disable:next force_cast
    unsafeDowncast(FBDeviceEraseCommands(device: target as! FBDevice), to: self)
  }

  init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: EraseCommands

  public func erase() async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    let logger = device.logger?.withName("erase_\(device.udid)") ?? FBControlCoreGlobalConfiguration.defaultLogger
    try await device.activate()
    let operation = FBDeviceEraseOperation(device: device, logger: logger)
    try await operation.erase()
    logger.log("Device erase finished successfully \(operation)")
  }
}

// MARK: - FBDevice+EraseCommands

extension FBDevice: EraseCommands {

  public func erase() async throws {
    try await eraseCommands().erase()
  }
}
