/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

@objc public final class FBCodeCoverageRequest: NSObject {

  @objc public let collect: Bool
  @objc public let format: FBCodeCoverageFormat
  @objc public let shouldEnableContinuousCoverageCollection: Bool

  @objc public init(collect: Bool, format: FBCodeCoverageFormat, enableContinuousCoverageCollection: Bool) {
    self.collect = collect
    self.format = format
    self.shouldEnableContinuousCoverageCollection = enableContinuousCoverageCollection
    super.init()
  }
}
