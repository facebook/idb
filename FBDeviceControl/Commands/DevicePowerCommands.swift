/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public final class FBDevicePowerCommands {
  private weak var device: FBDevice?

  public class func commands(with device: FBDevice) -> FBDevicePowerCommands {
    FBDevicePowerCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
  }

  fileprivate func sendRelayCommand(_ request: String) async throws {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    try await device.withServiceConnection("com.apple.mobile.diagnostics_relay") { connection in
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
    try await power.sendRelayCommand("Shutdown")
  }

  public func reboot() async throws {
    try await power.sendRelayCommand("Restart")
  }
}
