/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc(FBDevicePowerCommands)
public class FBDevicePowerCommands: NSObject, FBiOSTargetCommand {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBPowerCommands (legacy FBFuture entry points)

  public func shutdown() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await sendRelayCommandAsync("Shutdown")
      return NSNull()
    }
  }

  public func reboot() -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await sendRelayCommandAsync("Restart")
      return NSNull()
    }
  }

  // MARK: - Async

  fileprivate func sendRelayCommandAsync(_ request: String) async throws {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    try await withFBFutureContext(device.startService("com.apple.mobile.diagnostics_relay")) { connection in
      guard let result = try connection.sendAndReceiveMessage(["Request": request]) as? NSDictionary else {
        throw FBControlCoreError.describe("Unexpected response").build()
      }
      if (result["Status"] as? String) != "Success" {
        throw FBControlCoreError.describe("Not successful \(result)").build()
      }
    }
  }
}

// MARK: - FBDevice+AsyncPowerCommands

extension FBDevice: AsyncPowerCommands {

  public func shutdown() async throws {
    try await powerCommands().sendRelayCommandAsync("Shutdown")
  }

  public func reboot() async throws {
    try await powerCommands().sendRelayCommandAsync("Restart")
  }
}
