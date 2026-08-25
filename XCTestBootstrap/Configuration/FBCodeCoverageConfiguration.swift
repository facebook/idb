/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The code-coverage formats, with the member names the `NS_ENUM` importer produced.
public enum FBCodeCoverageFormat: UInt, Sendable {
  case exported = 0
  case raw = 1
}

public struct FBCodeCoverageConfiguration: Sendable, CustomStringConvertible {

  public let coverageDirectory: String
  public let format: FBCodeCoverageFormat
  public let shouldEnableContinuousCoverageCollection: Bool

  public init(directory coverageDirectory: String, format: FBCodeCoverageFormat, enableContinuousCoverageCollection: Bool) {
    self.coverageDirectory = coverageDirectory
    self.format = format
    self.shouldEnableContinuousCoverageCollection = enableContinuousCoverageCollection
  }

  public var description: String {
    "Coverage Directory \(coverageDirectory) | Format \(format.rawValue) | Enable Continuous Coverage Collection \(shouldEnableContinuousCoverageCollection)"
  }
}
