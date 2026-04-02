/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import XCTestBootstrap

@objc public final class FBXCTestReporterConfiguration: NSObject {

  @objc public let resultBundlePath: String?
  @objc public let coverageConfiguration: FBCodeCoverageConfiguration?
  @objc public let logDirectoryPath: String?
  @objc public let binariesPaths: [String]
  @objc public let reportAttachments: Bool
  @objc public let reportResultBundle: Bool

  @objc public init(resultBundlePath: String?, coverageConfiguration: FBCodeCoverageConfiguration?, logDirectoryPath: String?, binariesPaths: [String]?, reportAttachments: Bool, reportResultBundle: Bool) {
    self.resultBundlePath = resultBundlePath
    self.coverageConfiguration = coverageConfiguration
    self.logDirectoryPath = logDirectoryPath
    self.binariesPaths = binariesPaths ?? []
    self.reportAttachments = reportAttachments
    self.reportResultBundle = reportResultBundle
    super.init()
  }

  public override var description: String {
    let coverageDesc = coverageConfiguration.map { "\($0)" } ?? "(null)"
    return "Result Bundle \(resultBundlePath ?? "(null)") | Coverage \(coverageDesc) | Log Path \(logDirectoryPath ?? "(null)") | Binaries Paths \(FBCollectionInformation.oneLineDescription(from: binariesPaths)) | Report Attachments \(reportAttachments ? 1 : 0) | Report Restul Bundle \(reportResultBundle ? 1 : 0)"
  }
}
