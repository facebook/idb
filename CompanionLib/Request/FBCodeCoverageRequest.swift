/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

public struct FBCodeCoverageRequest: Sendable {

  public let collect: Bool
  public let format: FBCodeCoverageFormat
  public let shouldEnableContinuousCoverageCollection: Bool

  public init(collect: Bool, format: FBCodeCoverageFormat, enableContinuousCoverageCollection: Bool) {
    self.collect = collect
    self.format = format
    self.shouldEnableContinuousCoverageCollection = enableContinuousCoverageCollection
  }
}
