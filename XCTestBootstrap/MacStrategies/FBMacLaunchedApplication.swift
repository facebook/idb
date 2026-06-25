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

  public func waitForTermination() async throws {
    throw FBControlCoreError.describe("Awaiting termination is not supported for macOS applications").build()
  }

  public func terminate() async throws {
    guard let device else { return }
    try await bridgeFBFutureVoid(device.killApplication(withBundleID: bundleID))
  }
}
