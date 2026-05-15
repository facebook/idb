/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public final class FBCodeCoverageConfiguration: NSObject {

  @objc public let coverageDirectory: String
  @objc public let format: FBCodeCoverageFormat
  @objc public let shouldEnableContinuousCoverageCollection: Bool

  @objc public init(directory coverageDirectory: String, format: FBCodeCoverageFormat, enableContinuousCoverageCollection: Bool) {
    self.coverageDirectory = coverageDirectory
    self.format = format
    self.shouldEnableContinuousCoverageCollection = enableContinuousCoverageCollection
    super.init()
  }

  public override var description: String {
    return "Coverage Directory \(coverageDirectory) | Format \(format.rawValue) | Enable Continuous Coverage Collection \(shouldEnableContinuousCoverageCollection)"
  }
}
