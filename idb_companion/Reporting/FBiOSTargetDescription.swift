/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc final class FBiOSTargetDescription: NSObject, FBiOSTargetInfo, NSCopying {

  let uniqueIdentifier: String
  let udid: String
  let name: String
  let deviceType: FBDeviceType
  let architectures: [FBArchitecture]
  let osVersion: FBOSVersion
  let extendedInformation: [String: Any]
  let targetType: FBiOSTargetType
  let state: FBiOSTargetState

  private let model: FBDeviceModel?

  // These values are parsed into TargetDescription in idb/common/types.py, so need to be stable.
  private static let keyModel = "model"
  private static let keyName = "name"
  private static let keyOSVersion = "os_version"
  private static let keyState = "state"
  private static let keyType = "type"
  private static let keyUDID = "udid"

  @objc init?(target: FBiOSTargetInfo) {
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
    super.init()
  }

  func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  @objc var asJSON: [String: Any] {
    var representation: [String: Any] = [
      Self.keyModel: model as Any? ?? NSNull(),
      Self.keyName: name as Any? ?? NSNull(),
      Self.keyOSVersion: osVersion.name as Any? ?? NSNull(),
      Self.keyState: FBiOSTargetStateStringFromState(state),
      Self.keyType: FBiOSTargetTypeStringFromTargetType(targetType),
      Self.keyUDID: udid as Any? ?? NSNull(),
    ]
    for (key, value) in extendedInformation {
      representation[key] = value
    }
    return representation
  }
}
