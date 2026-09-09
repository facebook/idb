/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

public final class FBCoreSimulatorNotifier {

  private let handle: UInt64
  private let notifier: SimDeviceNotifier? // nil in test doubles

  public class func notifier(for simDevice: SimDevice, queue: DispatchQueue, block: @escaping @Sendable ([String: Any]) -> Void) -> FBCoreSimulatorNotifier {
    let notifier = simDevice.notificationManager as AnyObject?
    return FBCoreSimulatorNotifier(notifier: notifier, queue: queue, block: block)
  }

  public class func resolveLeavesState(_ state: FBiOSTargetState, for device: SimDevice) -> FBFuture<NSNull> {
    let future = FBMutableFuture<NSNull>()
    let queue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.resolve_state")
    nonisolated(unsafe) let futureRef = future
    let notifier = self.notifier(for: device, queue: queue) { info in
      guard let notification = info["notification"] as? String, notification == "device_state" else {
        return
      }
      guard let newStateNumber = info["new_state"] as? NSNumber else {
        return
      }
      let newState = FBiOSTargetState(rawValue: newStateNumber.uintValue)
      if newState == state {
        return
      }
      futureRef.resolve(withResult: NSNull())
    }
    return
      unsafeBitCast(future, to: FBFuture<NSNull>.self)
      .onQueue(
        queue,
        notifyOfCompletion: { (_: Any) in
          notifier.terminate()
        })
  }

  public func terminate() {
    notifier?.unregisterNotificationHandler(handle, error: nil)
  }

  class func notifier(for set: FBSimulatorSet, queue: DispatchQueue, block: @escaping @Sendable ([String: Any]) -> Void) -> FBCoreSimulatorNotifier {
    // notificationManager may be nil in test doubles (ObjC nil messaging returns nil).
    let notifier = (set.deviceSet as AnyObject).notificationManager as AnyObject?
    return FBCoreSimulatorNotifier(notifier: notifier, queue: queue, block: block)
  }

  private init(notifier: AnyObject?, queue: DispatchQueue, block: @escaping @Sendable ([String: Any]) -> Void) {
    // nil for test doubles; mirror ObjC nil-messaging with a 0 handle.
    guard let notifier = notifier as? SimDeviceNotifier else {
      self.notifier = nil
      self.handle = 0
      return
    }
    self.notifier = notifier
    self.handle = notifier.registerNotificationHandler(on: queue) { info in
      block((info as? [String: Any]) ?? [:])
    }
  }
}
