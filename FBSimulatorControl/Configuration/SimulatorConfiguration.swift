/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
@preconcurrency import Foundation

public struct FBSimulatorConfiguration: Equatable, Hashable, CustomStringConvertible, Sendable {

  public let device: DeviceType
  public let os: OSVersion
  public let deviceTypeIdentifier: String?
  public let runtimeIdentifier: String?
  public let runtimeBuildVersion: String?

  public init(
    device: DeviceType, os: OSVersion, deviceTypeIdentifier: String? = nil,
    runtimeIdentifier: String? = nil, runtimeBuildVersion: String? = nil
  ) {
    self.device = device
    self.os = os
    self.deviceTypeIdentifier = deviceTypeIdentifier
    self.runtimeIdentifier = runtimeIdentifier
    self.runtimeBuildVersion = runtimeBuildVersion
  }

  // MARK: - Equatable, Hashable

  public static func == (lhs: FBSimulatorConfiguration, rhs: FBSimulatorConfiguration) -> Bool {
    lhs.deviceIdentity == rhs.deviceIdentity && lhs.runtimeIdentity == rhs.runtimeIdentity
      && lhs.runtimeBuildVersion == rhs.runtimeBuildVersion
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(deviceIdentity)
    hasher.combine(runtimeIdentity)
    hasher.combine(runtimeBuildVersion)
  }

  private var deviceIdentity: String { deviceTypeIdentifier ?? device.model.rawValue }
  private enum RuntimeIdentity: Hashable {
    case identifier(String)
    case metadata(name: String, version: String)
  }

  private var runtimeIdentity: RuntimeIdentity {
    if let runtimeIdentifier {
      return .identifier(runtimeIdentifier)
    }
    return .metadata(name: os.name.rawValue, version: os.versionString)
  }

  public var description: String {
    "Device '\(device.model.rawValue)' | OS Version '\(os.name.rawValue)'"
  }
}
