/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBDeviceControl
import Foundation

/// A scripted restorable device: the notifications MobileDevice delivers as a device attaches and
/// detaches, and the `AMSEraseDevice` call that reboots it.
///
/// Neither registering for notifications nor erasing hands its callback a ref to recover a fake
/// from, so the fake in use is held statically and suites using it must be serialized. The device
/// itself travels as the `AMRestorableDeviceRef` each notification carries.
final class FakeRestorableDevice: NSObject {

  nonisolated(unsafe) fileprivate static var current: FakeRestorableDevice?

  let ecid: UInt

  /// The progress the erase callback reports. `-10` is what a device that accepted the erase sends.
  var eraseProgress: Int32 = -10

  /// Every call made, in order, as `event` or `event:detail`.
  private(set) var events: [String] = []

  private var listener: (callback: AMRestorableDeviceNotificationCallback, context: UnsafeMutableRawPointer?)?

  init(ecid: UInt) {
    self.ecid = ecid
  }

  /// Fills the restorable and erase entries of `calls` with this fake, which becomes the one they
  /// reach.
  ///
  /// Registering delivers the device's attach notification, and erasing reports `eraseProgress`
  /// then detaches and reattaches the device as it reboots. Each arrives asynchronously on the main
  /// queue, as MobileDevice's would on its own.
  func install(into calls: inout AMDCalls) {
    FakeRestorableDevice.current = self

    calls.RestorableDeviceRegisterForNotifications = { callback, context, _, _ in
      guard let device = FakeRestorableDevice.current, let callback else {
        return 0
      }
      device.events.append("register")
      device.listener = (callback, context)
      DispatchQueue.main.async { device.notify(.connected) }
      return 1
    }
    calls.RestorableDeviceUnregisterForNotifications = { _ in
      FakeRestorableDevice.current?.events.append("unregister")
      FakeRestorableDevice.current?.listener = nil
      return 0
    }
    calls.RestorableDeviceGetECID = { ref in
      (ref as? FakeRestorableDevice)?.ecid ?? 0
    }
    calls.RestorableDeviceGetState = { _ in
      AMRestorableDeviceState.bootedOS.rawValue
    }
    calls.RestorableDeviceGetChipID = { _ in 0 }
    calls.RestorableDeviceGetDeviceClass = { _ in 0 }
    calls.RestorableDeviceGetLocationID = { _ in 0 }
    calls.RestorableDeviceCopySerialNumber = { _ in nil }
    calls.RestorableDeviceCopyUserFriendlyName = { _ in nil }
    calls.RestorableDeviceCopyProductString = { _ in nil }

    calls.AMSInitialize = { _ in 0 }
    calls.AMSEraseDevice = { udid, callback, context in
      guard let device = FakeRestorableDevice.current, let callback else {
        return 1
      }
      let udid = (udid as String?) ?? ""
      device.events.append("erase:\(udid)")
      DispatchQueue.main.async {
        device.events.append("erase_callback:\(device.eraseProgress)")
        _ = callback(udid, device.eraseProgress, context)
        device.notify(.disconnected)
        device.notify(.connected)
      }
      return 0
    }
  }

  private func notify(_ status: AMRestorableDeviceNotificationType) {
    guard let listener else {
      return
    }
    events.append(status == .connected ? "connected" : "disconnected")
    listener.callback(self, status, listener.context)
  }
}
