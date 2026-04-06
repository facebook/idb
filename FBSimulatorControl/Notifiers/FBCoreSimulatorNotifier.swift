/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

@objc(FBCoreSimulatorNotifier)
public final class FBCoreSimulatorNotifier: NSObject {

  // MARK: - Properties

  private let handle: UInt64
  private let notifierObj: AnyObject? // SimDeviceNotifier (nil in test doubles)

  // MARK: - Public

  @objc(notifierForSimDevice:queue:block:)
  public class func notifier(for simDevice: SimDevice, queue: DispatchQueue, block: @escaping @Sendable ([String: Any]) -> Void) -> FBCoreSimulatorNotifier {
    let notifier = simDevice.notificationManager as AnyObject?
    return FBCoreSimulatorNotifier(notifier: notifier, queue: queue, block: block)
  }

  @objc(resolveLeavesState:forSimDevice:)
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

  @objc
  public func terminate() {
    guard let notifier = notifierObj else { return }
    (notifier as! SimDeviceNotifier).unregisterNotificationHandler(handle, error: nil)
  }

  // MARK: - Internal

  @objc(notifierForSet:queue:block:)
  class func notifier(for set: FBSimulatorSet, queue: DispatchQueue, block: @escaping @Sendable ([String: Any]) -> Void) -> FBCoreSimulatorNotifier {
    // notificationManager may be nil in test doubles (ObjC nil messaging returns nil).
    let notifier = (set.deviceSet as AnyObject).notificationManager as AnyObject?
    return FBCoreSimulatorNotifier(notifier: notifier, queue: queue, block: block)
  }

  // MARK: - Private

  private init(notifier: AnyObject?, queue: DispatchQueue, block: @escaping @Sendable ([String: Any]) -> Void) {
    self.notifierObj = notifier
    guard let notifierObj = notifier else {
      // nil notifier (test doubles) — mimic ObjC nil messaging returning 0
      self.handle = 0
      super.init()
      return
    }
    let handler: @Sendable ([AnyHashable: Any]?) -> Void = { info in
      block((info as? [String: Any]) ?? [:])
    }
    // The SimDeviceNotifier protocol has two registration methods:
    // 1. registerNotificationHandlerOnQueue:handler: (preferred, dispatches on given queue)
    // 2. registerNotificationHandler: (fallback, no queue — we dispatch manually)
    // Both have OS_dispatch_queue type ambiguity in Swift, so we use objc_msgSend via method(for:).
    // Closures must be explicitly bridged to @convention(block) for proper ObjC block semantics.
    let onQueueSelector = NSSelectorFromString("registerNotificationHandlerOnQueue:handler:")
    if notifierObj.responds(to: onQueueSelector) {
      let handlerBlock: @convention(block) ([AnyHashable: Any]?) -> Void = handler
      let handlerObj = unsafeBitCast(handlerBlock, to: AnyObject.self)
      typealias RegisterOnQueueFn = @convention(c) (AnyObject, Selector, DispatchQueue, AnyObject) -> UInt64
      let imp = unsafeBitCast(notifierObj.method(for: onQueueSelector), to: RegisterOnQueueFn.self)
      self.handle = imp(notifierObj, onQueueSelector, queue, handlerObj)
    } else {
      let fallbackSelector = NSSelectorFromString("registerNotificationHandler:")
      let wrappedBlock: @convention(block) ([AnyHashable: Any]?) -> Void = { info in
        nonisolated(unsafe) let infoRef = info
        queue.async {
          handler(infoRef)
        }
      }
      let wrappedObj = unsafeBitCast(wrappedBlock, to: AnyObject.self)
      typealias RegisterFn = @convention(c) (AnyObject, Selector, AnyObject) -> UInt64
      let imp = unsafeBitCast(notifierObj.method(for: fallbackSelector), to: RegisterFn.self)
      self.handle = imp(notifierObj, fallbackSelector, wrappedObj)
    }
    super.init()
  }
}
