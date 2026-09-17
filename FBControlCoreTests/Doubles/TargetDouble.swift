/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore

final class TargetDouble: TargetInfo {

  var uniqueIdentifier: String = ""
  var udid: String = ""
  var name: String = ""
  var state: FBiOSTargetState = .unknown
  var targetType: FBiOSTargetType = .simulator
  var deviceType: DeviceType = .generic(withName: "TargetDouble")
  var osVersion: OSVersion = .generic(withName: "TargetDouble")
  var architectures: [FBArchitecture] = []
  var extendedInformation: [String: Any] { [:] }
}
