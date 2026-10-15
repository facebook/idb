/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public final class TestManagerContext: CustomStringConvertible {

  public let sessionIdentifier: UUID
  public let timeout: TimeInterval
  public let testHostLaunchConfiguration: ApplicationLaunchConfiguration
  public let testedApplicationAdditionalEnvironment: [String: String]
  public let testConfiguration: TestConfiguration

  public init(
    sessionIdentifier: UUID,
    timeout: TimeInterval,
    testHostLaunchConfiguration: ApplicationLaunchConfiguration,
    testedApplicationAdditionalEnvironment: [String: String],
    testConfiguration: TestConfiguration
  ) {
    self.sessionIdentifier = sessionIdentifier
    self.timeout = timeout
    self.testHostLaunchConfiguration = testHostLaunchConfiguration
    self.testedApplicationAdditionalEnvironment = testedApplicationAdditionalEnvironment
    self.testConfiguration = testConfiguration
  }

  public var description: String {
    "Test Host \(testHostLaunchConfiguration) | Session ID \(sessionIdentifier.uuidString) | Timeout \(timeout)"
  }
}
