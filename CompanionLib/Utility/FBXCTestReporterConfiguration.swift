/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

public struct FBXCTestReporterConfiguration {

  public let resultBundlePath: String?
  public let coverageConfiguration: FBCodeCoverageConfiguration?
  public let logDirectoryPath: String?
  public let binariesPaths: [String]
  public let reportAttachments: Bool
  public let reportResultBundle: Bool

  public init(resultBundlePath: String?, coverageConfiguration: FBCodeCoverageConfiguration?, logDirectoryPath: String?, binariesPaths: [String]?, reportAttachments: Bool, reportResultBundle: Bool) {
    self.resultBundlePath = resultBundlePath
    self.coverageConfiguration = coverageConfiguration
    self.logDirectoryPath = logDirectoryPath
    self.binariesPaths = binariesPaths ?? []
    self.reportAttachments = reportAttachments
    self.reportResultBundle = reportResultBundle
  }

}

// MARK: - CustomStringConvertible

extension FBXCTestReporterConfiguration: CustomStringConvertible {

  public var description: String {
    let coverageDesc = coverageConfiguration.map { "\($0)" } ?? "(null)"
    return "Result Bundle \(resultBundlePath ?? "(null)") | Coverage \(coverageDesc) | Log Path \(logDirectoryPath ?? "(null)") | Binaries Paths \(FBCollectionInformation.oneLineDescription(from: binariesPaths)) | Report Attachments \(reportAttachments ? 1 : 0) | Report Restul Bundle \(reportResultBundle ? 1 : 0)"
  }
}
