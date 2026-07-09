/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import XCTestBootstrap

@objc public final class FBIDBAppHostedTestConfiguration: NSObject {

  @objc public let testLaunchConfiguration: FBTestLaunchConfiguration
  @objc public let coverageConfiguration: FBCodeCoverageConfiguration?

  @objc public init(testLaunchConfiguration: FBTestLaunchConfiguration, coverageConfiguration: FBCodeCoverageConfiguration?) {
    self.testLaunchConfiguration = testLaunchConfiguration
    self.coverageConfiguration = coverageConfiguration
    super.init()
  }
}
