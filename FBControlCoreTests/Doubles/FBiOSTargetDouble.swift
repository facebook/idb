/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore

/// A stub implementation of FBiOSTarget for testing.
final class FBiOSTargetDouble: NSObject, FBiOSTarget {

  // MARK: FBiOSTargetInfo - writable properties for test configuration

  var uniqueIdentifier: String = ""
  var udid: String = ""
  var name: String = ""
  var auxillaryDirectory: String = ""
  var customDeviceSetPath: String?
  var state: FBiOSTargetState = .unknown
  var targetType: FBiOSTargetType = .simulator
  var deviceType: FBDeviceType!
  var osVersion: FBOSVersion!

  // MARK: FBiOSTarget - synthesized properties

  var architectures: [FBArchitecture] = []
  var logger: (any FBControlCoreLogger)?
  var platformRootDirectory: String = ""
  var runtimeRootDirectory: String = ""
  var screenInfo: FBiOSTargetScreenInfo?
  var temporaryDirectory: FBTemporaryDirectory!

  // MARK: FBiOSTargetCommand

  @objc(commandsWithTarget:)
  static func commands(with target: any FBiOSTarget) -> Self {
    return self.init()
  }

  // MARK: FBiOSTarget

  var workQueue: DispatchQueue { .main }

  var asyncQueue: DispatchQueue { .global(qos: .userInitiated) }

  @objc(compare:)
  func compare(_ target: any FBiOSTarget) -> ComparisonResult {
    return FBiOSTargetComparison(self, target)
  }

  var extendedInformation: [String: Any] { [:] }

  func requiresBundlesToBeSigned() -> Bool { false }

  func replacementMapping() -> [String: String] { [:] }

  func environmentAdditions() -> [String: String] { [:] }

}
