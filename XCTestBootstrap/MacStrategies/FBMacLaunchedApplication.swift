/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The way termination-waiting fails on macOS applications, as data rather than an assembled string.
public enum FBMacLaunchedApplicationError: Error, LocalizedError {
  case awaitingTerminationUnsupported

  public var errorDescription: String? {
    switch self {
    case .awaitingTerminationUnsupported:
      return "Awaiting termination is not supported for macOS applications"
    }
  }
}

public final class FBMacLaunchedApplication: FBLaunchedApplication {

  public let bundleID: String
  public let processIdentifier: pid_t
  private weak var device: FBMacDevice?
  private let queue: DispatchQueue

  public init(bundleID: String, processIdentifier: pid_t, device: FBMacDevice, queue: DispatchQueue) {
    self.bundleID = bundleID
    self.processIdentifier = processIdentifier
    self.device = device
    self.queue = queue
  }

  public func waitForTermination() async throws {
    throw FBMacLaunchedApplicationError.awaitingTerminationUnsupported
  }

  public func terminate() async throws {
    guard let device else { return }
    try await bridgeFBFutureVoid(device.killApplication(withBundleID: bundleID))
  }
}
