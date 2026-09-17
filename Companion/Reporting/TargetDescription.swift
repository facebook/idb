/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public final class TargetDescription: TargetInfo {

  public let uniqueIdentifier: String
  public let udid: String
  public let name: String
  public let deviceType: DeviceType
  public let architectures: [FBArchitecture]
  public let osVersion: OSVersion
  public let extendedInformation: [String: Any]
  public let targetType: FBTargetType
  public let state: FBTargetState

  private let model: DeviceModel?

  // These values are parsed into TargetDescription in idb/common/types.py, so need to be stable.
  private static let keyModel = "model"
  private static let keyName = "name"
  private static let keyOSVersion = "os_version"
  private static let keyState = "state"
  private static let keyType = "type"
  private static let keyUDID = "udid"

  public init(target: TargetInfo) {
    self.extendedInformation = target.extendedInformation
    self.model = target.deviceType.model
    self.name = target.name
    self.osVersion = target.osVersion
    self.state = target.state
    self.targetType = target.targetType
    self.udid = target.udid
    self.uniqueIdentifier = target.uniqueIdentifier
    self.deviceType = target.deviceType
    self.architectures = target.architectures
  }

  public var asJSON: [String: Any] {
    var representation: [String: Any] = [
      Self.keyModel: model.map { $0.rawValue as Any } ?? NSNull(),
      Self.keyName: name as Any? ?? NSNull(),
      Self.keyOSVersion: osVersion.name.rawValue,
      Self.keyState: state.stateString.rawValue,
      Self.keyType: targetType.stringRepresentation,
      Self.keyUDID: udid as Any? ?? NSNull(),
    ]
    for (key, value) in extendedInformation {
      representation[key] = value
    }
    return representation
  }
}
