/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import IDBGRPCSwift

final class XctestRunRequestValueTransformer {

  func transform(value request: Idb_XctestRunRequest) -> FBXCTestRunRequest? {
    let testsToRun = request.testsToRun.isEmpty ? nil : Set(request.testsToRun)
    switch request.mode.mode {
    case .logic:
      return FBXCTestRunRequest.logicTest(withTestBundleID: request.testBundleID,
                                          environment: request.environment,
                                          arguments: request.arguments,
                                          testsToRun: testsToRun,
                                          testsToSkip: Set(request.testsToSkip),
                                          testTimeout: request.timeout as NSNumber,
                                          reportActivities: request.reportActivities,
                                          reportAttachments: request.reportAttachments,
                                          coverageRequest: extractCodeCoverage(from: request),
                                          collectLogs: request.collectLogs,
                                          waitForDebugger: request.waitForDebugger)
    case let .application(app):
      return FBXCTestRunRequest.applicationTest(withTestBundleID: request.testBundleID,
                                                appBundleID: app.appBundleID,
                                                environment: request.environment,
                                                arguments: request.arguments,
                                                testsToRun: testsToRun,
                                                testsToSkip: Set(request.testsToSkip),
                                                testTimeout: request.timeout as NSNumber,
                                                reportActivities: request.reportActivities,
                                                reportAttachments: request.reportAttachments,
                                                coverageRequest: extractCodeCoverage(from: request),
                                                collectLogs: request.collectLogs,
                                                waitForDebugger: request.waitForDebugger)
    case let .ui(ui):
      return FBXCTestRunRequest.uiTest(withTestBundleID: request.testBundleID,
                                       appBundleID: ui.appBundleID,
                                       testHostAppBundleID: ui.testHostAppBundleID,
                                       environment: request.environment,
                                       arguments: request.arguments,
                                       testsToRun: testsToRun,
                                       testsToSkip: Set(request.testsToSkip),
                                       testTimeout: request.timeout as NSNumber,
                                       reportActivities: request.reportActivities,
                                       reportAttachments: request.reportAttachments,
                                       coverageRequest: extractCodeCoverage(from: request),
                                       collectLogs: request.collectLogs)
    case .none:
      return nil
    }
  }

  private func extractCodeCoverage(from request: Idb_XctestRunRequest) -> FBCodeCoverageRequest {
    if request.hasCodeCoverage {
      switch request.codeCoverage.format {
      case .raw:
        return FBCodeCoverageRequest(collect: request.codeCoverage.collect, format: .raw)
      case .exported, .UNRECOGNIZED:
        return FBCodeCoverageRequest(collect: request.codeCoverage.collect, format: .exported)
      }
    }
    // fallback to deprecated request field for backwards compatibility
    return FBCodeCoverageRequest(collect: request.collectCoverage, format: .exported)
  }

}
