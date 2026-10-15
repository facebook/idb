/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@testable import FBSimulatorControl
import Foundation

final class SimulatorNotificationFixture {
  let device: SimulatorNotificationDeviceDouble
  let simulator: Simulator
  private let directory: URL

  init(supportsStateRead: Bool = true) throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let audio = directory.appendingPathComponent(SimulatorAudioSettings.relativePath)
    try FileManager.default.createDirectory(at: audio.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(
      fromPropertyList: ["sim_volume": 60, "sim_ringer_state": 1], format: .binary, options: 0)
    try data.write(to: audio)
    device = SimulatorNotificationDeviceDouble(dataPath: directory.path, supportsStateRead: supportsStateRead)
    simulator = SimulatorTestSupport.testableSimulator(withDevice: device)
  }

  deinit { try? FileManager.default.removeItem(at: directory) }
}

// SAFETY: `lock` guards the notification callbacks and all mutable setting values.
final class SimulatorNotificationDeviceDouble: NSObject, SimDeviceNotifier, @unchecked Sendable {
  @objc let UDID = NSUUID()
  @objc let state: UInt64 = 3
  @objc let dataPath: String
  private let supportsStateRead: Bool
  private let lock = NSLock()
  private var style = 1
  private var size = 4
  private var notificationState: UInt64 = 0
  private var stateReadCount = 0
  private var stateHandler: (([AnyHashable: Any]?) -> Void)?
  private var handler: ((String) -> Void)?
  private var name: String?
  private let token = SimulatorNotificationTokenDouble()
  private var removalCount = 0

  init(dataPath: String, supportsStateRead: Bool = true) {
    self.dataPath = dataPath
    self.supportsStateRead = supportsStateRead
  }

  var observedName: String? { lock.withLock { name } }
  var cancelled: Bool { token.invalidated && lock.withLock { removalCount > 0 } }
  var stateReads: Int { lock.withLock { stateReadCount } }
  var stateRemovals: Int { lock.withLock { removalCount } }
  var tokenInvalidations: Int { token.invalidations }

  override func responds(to selector: Selector!) -> Bool {
    if selector == NSSelectorFromString("darwinNotificationGetState:name:error:") { return supportsStateRead }
    return super.responds(to: selector)
  }

  @objc func currentUIInterfaceStyle() -> Int { lock.withLock { style } }
  @objc func currentContentSizeCategory() -> Int { lock.withLock { size } }

  @objc func darwinNotificationGetState(
    _ state: UnsafeMutablePointer<UInt64>, name: String, error: AutoreleasingUnsafeMutablePointer<NSError?>?
  ) -> Bool {
    state.pointee = lock.withLock {
      stateReadCount += 1
      return notificationState
    }
    return true
  }

  @objc func observeDarwinNotification(
    _ name: String, onQueue: DispatchQueue, handler: @escaping (String) -> Void,
    completionHandler: @escaping (SimDeviceDarwinNotificationToken?, NSError?) -> Void
  ) {
    lock.withLock {
      self.name = name
      self.handler = handler
    }
    let native = Unmanaged<SimDeviceDarwinNotificationToken>.fromOpaque(Unmanaged.passUnretained(token).toOpaque()).takeUnretainedValue()
    completionHandler(native, nil)
  }

  func change(style: Int = 1, size: Int = 4, state: UInt64 = 0) {
    let callback = lock.withLock {
      self.style = style
      self.size = size
      notificationState = state
      return (handler, name)
    }
    if let handler = callback.0, let name = callback.1 { handler(name) }
  }

  func changeDeviceState(_ rawState: UInt64) {
    let callback = lock.withLock { stateHandler }
    callback?(["notification": "device_state", "new_state": NSNumber(value: rawState)])
  }

  func registerNotificationHandler(on queue: DispatchQueue?, handler: (([AnyHashable: Any]?) -> Void)?) -> UInt64 {
    lock.withLock { stateHandler = handler }
    return 1
  }

  func unregisterNotificationHandler(_ handle: UInt64, error: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> Bool {
    lock.withLock {
      removalCount += 1
      stateHandler = nil
    }
    return true
  }
}

// SAFETY: `lock` guards invalidation, which can run on a different thread from the test.
private final class SimulatorNotificationTokenDouble: NSObject, @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var invalidated: Bool { lock.withLock { count > 0 } }
  var invalidations: Int { lock.withLock { count } }
  @objc func invalidate() { lock.withLock { count += 1 } }
}
