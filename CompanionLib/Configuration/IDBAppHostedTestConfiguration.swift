/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBXCTestCore
import Foundation

public final class IDBAppHostedTestConfiguration {

  public let testLaunchConfiguration: TestLaunchConfiguration
  public let coverageConfiguration: CodeCoverageConfiguration?

  public init(testLaunchConfiguration: TestLaunchConfiguration, coverageConfiguration: CodeCoverageConfiguration?) {
    self.testLaunchConfiguration = testLaunchConfiguration
    self.coverageConfiguration = coverageConfiguration
  }
}
