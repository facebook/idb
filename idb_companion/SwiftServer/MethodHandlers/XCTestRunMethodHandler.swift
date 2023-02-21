/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation
import GRPC
import IDBGRPCSwift

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
    let operation = try await BridgeFuture.value(operationFuture)
    reporter.configuration = .init(legacy: operation.reporterConfiguration)

    _ = try await BridgeFuture.value(reporter.reportingTerminated)

    // TODO: operation.completed throws an error in case of binary crash. We should handle it gracefully
    try? await BridgeFuture.await(operation.completed)
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
                                          waitForDebugger: request.waitForDebugger,
                                          collectResultBundle: request.collectResultBundle)
    case let .application(app):
      return FBXCTestRunRequest.applicationTest(withTestBundleID: request.testBundleID,
                                                testHostAppBundleID: app.appBundleID,
                                                environment: request.environment,
                                                arguments: request.arguments,
                                                testsToRun: testsToRun,
                                                testsToSkip: Set(request.testsToSkip),
                                                testTimeout: request.timeout as NSNumber,
                                                reportActivities: request.reportActivities,
                                                reportAttachments: request.reportAttachments,
                                                coverageRequest: extractCodeCoverage(from: request),
                                                collectLogs: request.collectLogs,
                                                waitForDebugger: request.waitForDebugger,
                                                collectResultBundle: request.collectResultBundle)
    case let .ui(ui):
      return FBXCTestRunRequest.uiTest(withTestBundleID: request.testBundleID,
                                       testHostAppBundleID: ui.testHostAppBundleID,
                                       testTargetAppBundleID: ui.appBundleID,
                                       environment: request.environment,
                                       arguments: request.arguments,
                                       testsToRun: testsToRun,
                                       testsToSkip: Set(request.testsToSkip),
                                       testTimeout: request.timeout as NSNumber,
                                       reportActivities: request.reportActivities,
                                       reportAttachments: request.reportAttachments,
                                       coverageRequest: extractCodeCoverage(from: request),
                                       collectLogs: request.collectLogs,
                                       collectResultBundle: request.collectResultBundle)
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
