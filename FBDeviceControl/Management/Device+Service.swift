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
  func withServiceConnection<T>(
    _ service: String,
    _ body: (FBAMDServiceConnection) async throws -> T
  ) async throws -> T {
    guard let amDevice else {
      throw AMDeviceServiceError.notAMDeviceBacked(service: service)
    }
    return try await amDevice.withServiceConnection(service, body)
  }

  /// Starts a service whose connection outlives this call, handing ownership to the caller, who
  /// hands it back to `FBAMDevice.invalidateServiceConnection`.
  func openServiceConnection(_ service: String) async throws -> FBAMDServiceConnection {
    guard let amDevice else {
      throw AMDeviceServiceError.notAMDeviceBacked(service: service)
    }
    return try await amDevice.openServiceConnection(service)
  }

  /// Starts a device link service, invalidating the connection once `body` returns or throws.
  func withDeviceLinkClient<T>(
    _ service: String,
    _ body: (DeviceLinkClient) async throws -> T
  ) async throws -> T {
    guard let amDevice else {
      throw AMDeviceServiceError.notAMDeviceBacked(service: service)
    }
    return try await amDevice.withDeviceLinkClient(service, body)
  }

  /// Starts a service and wraps it in an AFC client, tearing both down once `body` returns or
  /// throws.
  func withAFCConnection<T>(
    _ service: String,
    calls afcCalls: AFCCalls = FBAFCConnection.defaultCalls,
    _ body: (FBAFCConnection) async throws -> T
  ) async throws -> T {
    guard let amDevice else {
      throw AMDeviceServiceError.notAMDeviceBacked(service: service)
    }
    return try await amDevice.withAFCConnection(service, calls: afcCalls, body)
  }
}
