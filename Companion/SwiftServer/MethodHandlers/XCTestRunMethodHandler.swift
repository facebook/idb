/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import CompanionUtilities
import FBControlCore
import FBSimulatorControl
import Foundation
import GRPC
import IDBGRPCSwift
import XCTestBootstrap

struct XCTestRunMethodHandler {

  let target: any FBiOSTarget
  let commandExecutor: IDBCommandExecutor
  let reporter: EventReporter
  let targetLogger: FBControlCoreLogger
  let logger: IDBLogger

  func handle(request: Idb_XctestRunRequest, responseStream: GRPCAsyncResponseStreamWriter<Idb_XctestRunResponse>, context: GRPCAsyncServerCallContext) async throws {
    guard let request = transform(value: request) else {
      throw GRPCStatus(code: .invalidArgument, message: "failed to create XCTestRunRequest")
    }

    let reporter = IDBXCTestReporter(responseStream: responseStream, queue: target.workQueue, logger: logger)

    let operation = try await commandExecutor.xctest_run(
      request,
      reporter: reporter,
      logger: FBControlCoreLoggerFactory.logger(to: reporter))
    reporter.configuration = .init(legacy: operation.reporterConfiguration)

    do {
      try await operation.awaitCompletion()
    } catch let error as NSError {
      // We should ignore errors that came from test binary. Like when exception is throwed or binary crashed.
      if error.domain != FBTestErrorDomain {
        throw error
      }
    }

    _ = try await reporter.awaitReportingTerminated()
  }

  func transform(value request: Idb_XctestRunRequest) -> XCTestRunRequest? {
    let testsToRun = request.testsToRun.isEmpty ? nil : Set(request.testsToRun)
    switch request.mode.mode {
    case .logic:
      return XCTestRunRequest.logicTest(
        withTestBundleID: request.testBundleID,
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
      return XCTestRunRequest.applicationTest(
        withTestBundleID: request.testBundleID,
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
      return XCTestRunRequest.uiTest(
        withTestBundleID: request.testBundleID,
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

  private func extractCodeCoverage(from request: Idb_XctestRunRequest) -> CodeCoverageRequest {
    if request.hasCodeCoverage {
      switch request.codeCoverage.format {
      case .raw:
        return CodeCoverageRequest(collect: request.codeCoverage.collect, format: .raw, enableContinuousCoverageCollection: request.codeCoverage.enableContinuousCoverageCollection)
      case .exported, .UNRECOGNIZED:
        return CodeCoverageRequest(collect: request.codeCoverage.collect, format: .exported, enableContinuousCoverageCollection: request.codeCoverage.enableContinuousCoverageCollection)
      }
    }
    // fallback to deprecated request field for backwards compatibility
    return CodeCoverageRequest(collect: request.collectCoverage, format: .exported, enableContinuousCoverageCollection: request.codeCoverage.enableContinuousCoverageCollection)
  }
}
