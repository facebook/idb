/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore

final class FBiOSTargetDouble: FBiOSTarget {

  // MARK: FBiOSTargetInfo

  var uniqueIdentifier: String = ""
  var udid: String = ""
  var name: String = ""
  var auxillaryDirectory: String = ""
  var customDeviceSetPath: String?
  var state: FBiOSTargetState = .unknown
  var targetType: FBiOSTargetType = .simulator
  var deviceType: FBDeviceType = .generic(withName: "FBiOSTargetDouble")
  var osVersion: FBOSVersion = .generic(withName: "FBiOSTargetDouble")

  // MARK: FBiOSTarget

  var architectures: [FBArchitecture] = []
  var logger: any FBControlCoreLogger = FBControlCoreLoggerDouble()
  var platformRootDirectory: String { get async { "" } }
  var runtimeRootDirectory: String { get async { "" } }
  var screenInfo: FBiOSTargetScreenInfo?
  var temporaryDirectory: FBTemporaryDirectory = .temporaryDirectory(logger: FBControlCoreLoggerDouble())

  // MARK: FBiOSTargetCommand

  static func commands(with target: any FBiOSTarget) -> Self {
    return self.init()
  }

  // MARK: FBiOSTarget

  var workQueue: DispatchQueue { .main }

  var asyncQueue: DispatchQueue { .global(qos: .userInitiated) }

  func compare(_ target: any FBiOSTarget) -> ComparisonResult {
    return FBiOSTargetComparison(self, target)
  }

  var extendedInformation: [String: Any] { [:] }

  func requiresBundlesToBeSigned() -> Bool { false }

  func replacementMapping() -> [String: String] { [:] }

  func environmentAdditions() -> [String: String] { [:] }

}
