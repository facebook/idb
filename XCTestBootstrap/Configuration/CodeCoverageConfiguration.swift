/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum CodeCoverageFormat: UInt, Sendable {
  case exported = 0
  case raw = 1
}

public struct CodeCoverageConfiguration: Sendable, CustomStringConvertible {

  public let coverageDirectory: String
  public let format: CodeCoverageFormat
  public let shouldEnableContinuousCoverageCollection: Bool

  public init(directory coverageDirectory: String, format: CodeCoverageFormat, enableContinuousCoverageCollection: Bool) {
    self.coverageDirectory = coverageDirectory
    self.format = format
    self.shouldEnableContinuousCoverageCollection = enableContinuousCoverageCollection
  }

  public var description: String {
    "Coverage Directory \(coverageDirectory) | Format \(format.rawValue) | Enable Continuous Coverage Collection \(shouldEnableContinuousCoverageCollection)"
  }
}
