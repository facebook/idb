/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

extension FBDevice {

  /// Starts a service on the device, invalidating the connection once `body` returns or throws.
  ///
  /// The async counterpart of `startService`, which this mirrors including its restriction to
  /// AMDevice-backed devices.
  public func withServiceConnection<T>(
    _ service: String,
    _ body: (FBAMDServiceConnection) async throws -> T
  ) async throws -> T {
    guard let amDevice else {
      throw FBAMDeviceServiceError.notAMDeviceBacked(service: service)
    }
    return try await amDevice.withServiceConnection(service, body)
  }

  /// Starts a device link service, invalidating the connection once `body` returns or throws.
  public func withDeviceLinkClient<T>(
    _ service: String,
    _ body: (FBDeviceLinkClient) async throws -> T
  ) async throws -> T {
    guard let amDevice else {
      throw FBAMDeviceServiceError.notAMDeviceBacked(service: service)
    }
    return try await amDevice.withDeviceLinkClient(service, body)
  }
}
