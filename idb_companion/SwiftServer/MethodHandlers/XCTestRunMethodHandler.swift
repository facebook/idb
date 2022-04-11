/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import IDBGRPCSwift
import GRPC
import FBSimulatorControl

struct XCTestRunMethodHandler {

  let target: FBiOSTarget
  let commandExecutor: FBIDBCommandExecutor
  let reporter: FBEventReporter
  let targetLogger: FBControlCoreLogger
  let logger: FBIDBLogger

  func handle(request: Idb_XctestRunRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_XctestRunResponse>, context: GRPCAsyncServerCallContext) async throws {
    guard let request = transform(value: request) else {
      throw GRPCStatus(code: .invalidArgument, message: "failed to create FBXCTestRunRequest")
    }

    let reporter = IDBXCTestReporter(responseStream: responseStream, queue: target.workQueue, logger: logger)

    let operationFuture = commandExecutor.xctest_run(request,
                                                     reporter: reporter,
                                                     logger: FBControlCoreLoggerFactory.logger(to: reporter))
    let operation = try await FutureBox.value(operationFuture)
    reporter.configuration = .init(legacy: operation.reporterConfiguration)

    try await FutureBox.await(operation.completed)
    _ = try await FutureBox.value(reporter.reportingTerminated)
  }


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
