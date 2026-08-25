/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public class FBDevicePowerCommands: NSObject {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with device: FBDevice) -> FBDevicePowerCommands {
    FBDevicePowerCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - Private

  fileprivate func sendRelayCommand(_ request: String) async throws {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    try await withFBFutureContext(device.startService("com.apple.mobile.diagnostics_relay")) { connection in
      guard let result = try connection.sendAndReceiveMessage(["Request": request]) as? NSDictionary else {
        throw FBDiagnosticsRelayError.unexpectedResponse
      }
      if (result["Status"] as? String) != "Success" {
        throw FBDiagnosticsRelayError.unsuccessful(response: String(describing: result))
      }
    }
  }
}

// MARK: - FBDevice+PowerCommands

extension FBDevice: PowerCommands {

  public func shutdown() async throws {
    try await powerCommands().sendRelayCommand("Shutdown")
  }

  public func reboot() async throws {
    try await powerCommands().sendRelayCommand("Restart")
  }
}
