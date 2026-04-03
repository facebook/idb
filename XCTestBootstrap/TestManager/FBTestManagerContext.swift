/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc public final class FBTestManagerContext: NSObject, NSCopying {

  @objc public let sessionIdentifier: UUID
  @objc public let timeout: TimeInterval
  @objc public let testHostLaunchConfiguration: FBApplicationLaunchConfiguration
  @objc public let testedApplicationAdditionalEnvironment: [String: String]
  @objc public let testConfiguration: FBTestConfiguration

  @objc public init(
    sessionIdentifier: UUID,
    timeout: TimeInterval,
    testHostLaunchConfiguration: FBApplicationLaunchConfiguration,
    testedApplicationAdditionalEnvironment: [String: String],
    testConfiguration: FBTestConfiguration
  ) {
    self.sessionIdentifier = sessionIdentifier
    self.timeout = timeout
    self.testHostLaunchConfiguration = testHostLaunchConfiguration
    self.testedApplicationAdditionalEnvironment = testedApplicationAdditionalEnvironment
    self.testConfiguration = testConfiguration
    super.init()
  }

  public override var description: String {
    return "Test Host \(testHostLaunchConfiguration) | Session ID \(sessionIdentifier.uuidString) | Timeout \(timeout)"
  }

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }
}
