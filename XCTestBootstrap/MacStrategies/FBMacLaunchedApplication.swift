/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc public final class FBMacLaunchedApplication: NSObject, FBLaunchedApplication {

  @objc public let bundleID: String
  @objc public let processIdentifier: pid_t
  private weak var device: FBMacDevice?
  private let queue: DispatchQueue

  @objc public init(bundleID: String, processIdentifier: pid_t, device: FBMacDevice, queue: DispatchQueue) {
    self.bundleID = bundleID
    self.processIdentifier = processIdentifier
    self.device = device
    self.queue = queue
    super.init()
  }

  @objc public var applicationTerminated: FBFuture<NSNull> {
    let bundleID = self.bundleID
    let device = self.device
    let future = FBMutableFuture<AnyObject>()
    let result = future.onQueue(
      queue,
      respondToCancellation: { () -> FBFuture<NSNull> in
        if let device {
          return device.killApplication(withBundleID: bundleID)
        }
        return FBFuture(result: NSNull())
      })
    return unsafeBitCast(result, to: FBFuture<NSNull>.self)
  }
}
