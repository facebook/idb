/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/// Reads and writes the device's home screen through SpringBoardServices.
public struct DeviceSpringboardCommands {

  private let device: FBDevice

  // MARK: - Initializers

  public static func commands(with device: FBDevice) -> DeviceSpringboardCommands {
    DeviceSpringboardCommands(device: device)
  }

  internal init(device: FBDevice) {
    self.device = device
  }

  // MARK: - Icon layout

  public func iconLayout() async throws -> SpringboardIconLayout {
    try await withClient { client in
      try await client.getIconLayout()
    }
  }

  public func setIconLayout(_ layout: SpringboardIconLayout) async throws {
    try await withClient { client in
      try await client.setIconLayout(layout)
    }
  }

  public func rawIconState(formatVersion: UInt) async throws -> AnyObject {
    try await withClient { client in
      try await client.getRawIconState(formatVersion: formatVersion)
    }
  }

  public func iconMetrics() async throws -> [String: Any] {
    try await withClient { client in
      try await client.getHomeScreenIconMetrics()
    }
  }

  private func withClient<R>(
    body: (SpringboardServicesClient) async throws -> R
  ) async throws -> R {
    try await device.withServiceConnection(SpringboardServicesClient.serviceName) { connection in
      let client = SpringboardServicesClient(connection: connection, logger: device.logger)
      return try await body(client)
    }
  }
}
