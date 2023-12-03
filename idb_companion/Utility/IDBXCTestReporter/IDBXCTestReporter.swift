/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBSimulatorControl
import Foundation
import GRPC
import IDBCompanionUtilities
import IDBGRPCSwift
import XCTestBootstrap

extension IDBXCTestReporter {

  struct Configuration {

    let resultBundlePath: String

    let coverageConfiguration: FBCodeCoverageConfiguration?

    let logDirectoryPath: String?

    let binariesPath: [String]

    let reportAttachments: Bool

    let reportResultBundle: Bool

    init(legacy: FBXCTestReporterConfiguration) {
      self.resultBundlePath = legacy.resultBundlePath ?? ""
      self.coverageConfiguration = legacy.coverageConfiguration
      self.logDirectoryPath = legacy.logDirectoryPath
      self.binariesPath = legacy.binariesPaths ?? []
      self.reportAttachments = legacy.reportAttachments
      self.reportResultBundle = legacy.reportResultBundle
    }
  }

  struct CurrentTestInfo {
    var bundleName = ""
    var testClass = ""
    var testMethod = ""
    var activityRecords: [FBActivityRecord] = []
    var failureInfo: Idb_XctestRunResponse.TestRunInfo.TestRunFailureInfo?
    var otherFailures: [Idb_XctestRunResponse.TestRunInfo.TestRunFailureInfo] = []
  }
}

@objc final class IDBXCTestReporter: NSObject, FBXCTestReporter, FBDataConsumer {

  let reportingTerminated = FBMutableFuture<NSNumber>()
  var configuration: Configuration!

  @Atomic private var responseStream: GRPCAsyncResponseStreamWriter<Idb_XctestRunResponse>?

  private let queue: DispatchQueue
  private let logger: FBControlCoreLogger

  private let processUnderTestExitedMutable = FBMutableFuture<NSNull>()

  @Atomic private var currentInfo = CurrentTestInfo()

  init(responseStream: GRPCAsyncResponseStreamWriter<Idb_XctestRunResponse>, queue: DispatchQueue, logger: FBControlCoreLogger) {
    self._responseStream = .init(wrappedValue: responseStream)
    self.queue = queue
    self.logger = logger
  }

  // MARK: - FBDataConsumer implementation

  @objc func consumeData(_ data: Data) {
    let logOutput = String(data: data, encoding: .utf8) ?? ""
    let response = createResponse(logOutput: logOutput)
    write(response: response)
  }

  @objc func consumeEndOfFile() {
    // Implementation not required
  }

  // MARK: - FBXCTestReporter implementation

  @objc func processWaitingForDebugger(withProcessIdentifier pid: pid_t) {
    logger.info().log("Tests waiting for debugger. To debug run: lldb -p \(pid)")
    let response = Idb_XctestRunResponse.with {
      $0.status = .running
      $0.debugger = .with {
        $0.pid = UInt64(pid)
      }
    }

    write(response: response)
  }

  @objc func didBeginExecutingTestPlan() {
    // Implementation not required
  }

  @objc func didFinishExecutingTestPlan() {
    let response = Idb_XctestRunResponse.with {
      $0.status = .terminatedNormally
    }
    write(response: response)
  }

  @objc func processUnderTestDidExit() {
    processUnderTestExitedMutable.resolve(withResult: NSNull())
  }

  @objc func testSuite(_ testSuite: String, didStartAt startTime: String) {
    _currentInfo.sync { $0.bundleName = testSuite }
  }

  @objc func testCaseDidFinish(forTestClass testClass: String, method: String, with status: FBTestReportStatus, duration: TimeInterval, logs: [String]?) {
    do {
      let info = try createRunInfo(testClass: testClass, method: method, status: status, duration: duration, logs: logs ?? [])
      write(testRunInfo: info)
    } catch {
      _responseStream.sync { $0 = nil }
      reportingTerminated.resolveWithError(error)
    }
  }

  @objc func testCaseDidFail(forTestClass testClass: String, method: String, exceptions: [FBExceptionInfo]) {
    let currentInfo = self.currentInfo
    if testClass == currentInfo.testClass && method != currentInfo.testMethod {
      logger.log("Got failure info for \(testClass)/\(method) but the current known executing test is \(currentInfo.testClass)\(currentInfo.testMethod). Ignoring it")
      return
    }
    self._currentInfo.sync {
      if let firstExceptionInfo = exceptions.first {
        $0.failureInfo = createFailureInfo(exceptionInfo: firstExceptionInfo)
        $0.otherFailures = exceptions.dropFirst().map { createFailureInfo(exceptionInfo: $0) }
      } else {
        logger.log("No exceptions were returned in the failure. This shouldn't happen.")
      }
    }
  }

  @objc func testCaseDidStart(forTestClass testClass: String, method: String) {
    _currentInfo.sync {
      $0.testClass = testClass
      $0.testMethod = method
    }
  }

  @objc func testPlanDidFail(withMessage message: String) {
    let response = responseFor(crashMessage: message)
    write(response: response)
  }

  @objc func testCase(_ testClass: String, method: String, didFinishActivity activity: FBActivityRecord) {
    _currentInfo.sync {
      $0.activityRecords.append(activity)
    }
  }

  @objc func finished(with summary: FBTestManagerResultSummary) {
    // didFinishExecutingTestPlan should be used to signify completion instead
  }

  @objc func testHadOutput(_ output: String) {
    let response = createResponseExtractingFailureInfo(from: output)
    write(response: response)
  }

  @objc func handleExternalEvent(_ event: String) {
    let response = createResponseExtractingFailureInfo(from: event)
    write(response: response)
  }

  @objc func printReport() throws {
    // Warning! This method is bridged to swift incorrectly and loses bool return type. Adapt and use with extra care
  }

  @objc func didCrashDuringTest(_ error: Error) {
    let response = responseFor(crashMessage: error.localizedDescription)
    write(response: response)
  }

  // MARK: - Privates

  private func createRunInfo(testClass: String, method: String, status: FBTestReportStatus, duration: TimeInterval, logs: [String]) throws -> Idb_XctestRunResponse.TestRunInfo {

    defer { resetCurrentTestState() }

    return try _currentInfo.sync { currentInfo in

      var stackedActivities: [FBActivityRecord] = []
      currentInfo.activityRecords.sort(by: { $0.start < $1.start })

      while let activity = currentInfo.activityRecords.first {
        currentInfo.activityRecords.remove(at: 0)
        populateSubactivities(root: activity, remaining: &currentInfo.activityRecords)
        stackedActivities.append(activity)
      }

      return try Idb_XctestRunResponse.TestRunInfo.with {
        $0.bundleName = currentInfo.bundleName
        $0.className = testClass
        $0.methodName = method
        $0.status = status == .failed ? .failed : .passed
        $0.duration = duration
        if let failureInfo = currentInfo.failureInfo {
          $0.failureInfo = failureInfo
        }
        $0.logs = logs
        $0.activityLogs = try stackedActivities.map(translate(activity:))
        $0.otherFailures = currentInfo.otherFailures
      }
    }
  }

  private func translate(activity: FBActivityRecord) throws -> Idb_XctestRunResponse.TestRunInfo.TestActivity {
    let subactivities = activity.subactivities as! [FBActivityRecord]
    return try Idb_XctestRunResponse.TestRunInfo.TestActivity.with {
      $0.title = activity.title
      $0.duration = activity.duration
      $0.uuid = activity.uuid.uuidString
      $0.activityType = activity.activityType
      $0.start = activity.start.timeIntervalSince1970
      $0.finish = activity.finish.timeIntervalSince1970
      $0.name = activity.name
      if configuration.reportAttachments {
        $0.attachments = try activity.attachments.map { attachment in
          try .with {
            $0.payload = attachment.payload ?? Data()
            $0.name = attachment.name
            $0.timestamp = attachment.timestamp.timeIntervalSince1970
            $0.uniformTypeIdentifier = attachment.uniformTypeIdentifier
            if let userInfo = attachment.userInfo {
              $0.userInfoJson = try translate(attachmentUserInfo: userInfo)
            }
          }
        }
      }
      $0.subActivities = try subactivities.map(translate(activity:))
    }
  }

  private func translate(attachmentUserInfo userInfo: [AnyHashable: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: userInfo, options: [])
  }

  private func resetCurrentTestState() {
    _currentInfo.sync {
      $0.activityRecords.removeAll()
      $0.failureInfo = nil
      $0.testClass = ""
      $0.testMethod = ""
      $0.otherFailures.removeAll()
    }
  }

  private func populateSubactivities(root: FBActivityRecord, remaining: inout [FBActivityRecord]) {
    while let firstRemaining = remaining.first, root.start <= firstRemaining.start && firstRemaining.finish <= root.finish {
      remaining.remove(at: 0)
      populateSubactivities(root: firstRemaining, remaining: &remaining)
      root.subactivities.add(firstRemaining)
    }
  }

  private func write(testRunInfo: Idb_XctestRunResponse.TestRunInfo) {
    let response = Idb_XctestRunResponse.with {
      $0.status = .running
      $0.results = [testRunInfo]
    }
    write(response: response)
  }

  private func write(response: Idb_XctestRunResponse) {
    Task {
      do {
        switch response.status {
        case .terminatedNormally, .terminatedAbnormally:
          try await insertFinalDataThenWriteResponse(response: response)

        default:
          try await writeResponseFinal(response: response)
        }
      } catch {
        logger.log("Failed to write xctest run response \(error.localizedDescription)")
      }
    }
  }

  // TODO: Parallelism of execution was lost after rewriting this method to swift. Make this work in parallel again
  private func insertFinalDataThenWriteResponse(response: Idb_XctestRunResponse) async throws {
    var response = response

    if !configuration.resultBundlePath.isEmpty && configuration.reportResultBundle {
      do {
        let resultBundle = try await gzipFolder(at: configuration.resultBundlePath)
        response.resultBundle = .with {
          $0.data = resultBundle
        }
      } catch {
        logger.info().log("Failed to create result bundle \(error.localizedDescription)")
      }
    }

    if let coverageConfig = configuration.coverageConfiguration, !coverageConfig.coverageDirectory.isEmpty {
      do {
        let coverageData = try await getCoverageResponseData(config: coverageConfig)
        response.codeCoverageData = .with {
          $0.data = coverageData
        }
      } catch {
        logger.info().log("Failed to get coverage data: \(error.localizedDescription)")
      }
    }

    if let logDirectoryPath = configuration.logDirectoryPath {
      let data = try await gzipFolder(at: logDirectoryPath)
      response.logDirectory = .with {
        $0.data = data
      }
    }

    try await writeResponseFinal(response: response)
  }

  private func writeResponseFinal(response: Idb_XctestRunResponse) async throws {
    let shouldCloseStream = isLastMessage(responseStatus: response.status)

    let stream: GRPCAsyncResponseStreamWriter<Idb_XctestRunResponse>? = _responseStream.sync { storedStream in
      guard let responseStream = storedStream else { return nil }
      if shouldCloseStream {
        storedStream = nil
      }
      return responseStream
    }

    guard let responseStream = stream else {
      logger.error().log("writeResponse called, but the last response has already been written!")
      return
    }

    try await responseStream.send(response)

    if shouldCloseStream {
      logger.log("Test Reporting has finished with status \(response.status)")
      reportingTerminated.resolve(withResult: .init(value: response.status.rawValue))
    }
  }

  private func isLastMessage(responseStatus: Idb_XctestRunResponse.Status) -> Bool {
    return responseStatus == .terminatedNormally || responseStatus == .terminatedAbnormally
  }

  private func gzipFolder(at path: String) async throws -> Data {
    let task = FBArchiveOperations.createGzippedTarData(forPath: path,
                                                        queue: queue,
                                                        logger: logger)
    return try await BridgeFuture.value(task) as Data
  }

  private func getCoverageResponseData(config: FBCodeCoverageConfiguration) async throws -> Data {
    try await BridgeFuture.await(processUnderTestExitedMutable)
    switch config.format {
    case .exported:
      let data = try await getCoverageDataExported(config: config)
      return data as Data

    case .raw:
      return try await gzipFolder(at: config.coverageDirectory)

    default:
      throw FBControlCoreError.describe("Unsupported code coverage format")
    }
  }

  private func getCoverageDataExported(config: FBCodeCoverageConfiguration) async throws -> Data {
    let coverageDirectory = URL(fileURLWithPath: config.coverageDirectory)
    let profdataPath = coverageDirectory.appendingPathComponent("coverage.profdata")

    try await mergeRawCoverage(coverageDirectory: coverageDirectory, profdataPath: profdataPath)
    return try await exportCoverage(profdataPath: profdataPath, binariesPath: configuration.binariesPath)
  }

  private func mergeRawCoverage(coverageDirectory: URL, profdataPath: URL) async throws {
    let profraws = try FileManager.default
      .contentsOfDirectory(at: coverageDirectory, includingPropertiesForKeys: nil, options: [])
      .filter { $0.pathExtension == "profraw" }

    let mergeArgs: [String] = ["llvm-profdata", "merge", "-o", profdataPath.path]
      + profraws.map(\.path)

    let mergeProcessFuture = FBProcessBuilder<NSNull, NSData, NSString>
      .withLaunchPath("/usr/bin/xcrun", arguments: mergeArgs)
      .withStdOutInMemoryAsData()
      .withStdErrInMemoryAsString()
      .runUntilCompletion(withAcceptableExitCodes: nil)

    let mergeProcess = try await BridgeFuture.value(mergeProcessFuture)
    let exitCode = try await BridgeFuture.value(mergeProcess.exitCode)
    if exitCode != 0 {
      throw FBControlCoreError.describe("xcrun failed to export code coverage data \(exitCode.intValue) \(mergeProcess.stdErr ?? "")")
    }
  }

  private func exportCoverage(profdataPath: URL, binariesPath: [String]) async throws -> Data {
    let exportArgs: [String] = ["llvm-cov", "export", "-instr-profile", profdataPath.path]
      + binariesPath.reduce(into: []) {
        $0 += ["-object", $1]
      }
    let exportProcess = try await BridgeFuture.value(
      FBProcessBuilder<NSNull, NSData, NSString>
        .withLaunchPath("/usr/bin/xcrun", arguments: exportArgs)
        .withStdOutToInputStream()
        .withStdErrInMemoryAsString()
        .start()
    )

    let gzipProcessInput = FBProcessInput<OutputStream>.fromStream()
    let archiveFuture = FBArchiveOperations.createGzipData(from: gzipProcessInput as! FBProcessInput<AnyObject>, logger: self.logger)

    let oneMega = 1024 * 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: oneMega)
    defer {
      buffer.deallocate()
    }

    guard let exportOutputStream = exportProcess.stdOut
    else {
      throw FBControlCoreError.describe("xcrun llvm-cov export misconfigured. stdOut stream is nil")
    }
    exportOutputStream.open()

    let gzipInputStream = gzipProcessInput.contents
    gzipInputStream.open()
    while case let bytesRead = exportOutputStream.read(buffer, maxLength: oneMega), bytesRead > 0 {
      gzipInputStream.write(buffer, maxLength: bytesRead)
    }
    exportOutputStream.close()
    gzipInputStream.close()

    let exitCode = try await BridgeFuture.value(exportProcess.exitCode)
    if exitCode != 0 {
      throw FBControlCoreError.describe("xcrun failed to export code coverage data \(exitCode.intValue) \(exportProcess.stdErr ?? "")")
    }

    let archiveProcess = try await BridgeFuture.value(archiveFuture)
    let stdOut = archiveProcess.stdOut ?? NSData()
    return stdOut as Data
  }

  private func createFailureInfo(message: String, file: String?, line: UInt) -> Idb_XctestRunResponse.TestRunInfo.TestRunFailureInfo {
    return Idb_XctestRunResponse.TestRunInfo.TestRunFailureInfo.with {
      $0.failureMessage = message
      $0.file = file ?? ""
      $0.line = UInt64(line)
    }
  }

  private func createFailureInfo(exceptionInfo: FBExceptionInfo) -> Idb_XctestRunResponse.TestRunInfo.TestRunFailureInfo {
    return Idb_XctestRunResponse.TestRunInfo.TestRunFailureInfo.with {
      $0.failureMessage = exceptionInfo.message
      $0.file = exceptionInfo.file ?? ""
      $0.line = UInt64(exceptionInfo.line)
    }
  }

  private func responseFor(crashMessage: String) -> Idb_XctestRunResponse {
    defer { resetCurrentTestState() }

    let currentInfo = self.currentInfo
    let info = Idb_XctestRunResponse.TestRunInfo.with {
      $0.bundleName = currentInfo.bundleName
      $0.className = currentInfo.testClass
      $0.methodName = currentInfo.testMethod
      $0.failureInfo = currentInfo.failureInfo ?? .init()
      $0.failureInfo.failureMessage = crashMessage
      $0.status = .crashed
      $0.otherFailures = currentInfo.otherFailures
    }

    return Idb_XctestRunResponse.with {
      $0.status = .terminatedAbnormally
      $0.results = [info]
    }
  }

  private func createResponseExtractingFailureInfo(from logOutput: String) -> Idb_XctestRunResponse {
    extractFailureInfo(from: logOutput)
    return createResponse(logOutput: logOutput)
  }

  private func extractFailureInfo(from logOutput: String) {
    do {
      let regexp = try NSRegularExpression(pattern: "Assertion failed: (.*), function (.*), file (.*), line (\\d+).", options: .caseInsensitive)
      let log = logOutput as NSString
      if let result = regexp.firstMatch(in: logOutput, options: [], range: .init(location: 0, length: log.length)) {
        _currentInfo.sync {
          $0.failureInfo = failureInfoWith(message: log.substring(with: result.range(at: 1)),
                                           file: log.substring(with: result.range(at: 3)),
                                           line: UInt(log.substring(with: result.range(at: 4))) ?? 0)
        }
      }
    } catch {
      assertionFailure(error.localizedDescription)
      logger.error().log("Incorrect regexp \(error.localizedDescription)")
    }
  }

  private func createResponse(logOutput: String) -> Idb_XctestRunResponse {
    return Idb_XctestRunResponse.with {
      $0.status = .running
      $0.logOutput = [logOutput]
    }
  }

  private func failureInfoWith(message: String, file: String, line: UInt) -> Idb_XctestRunResponse.TestRunInfo.TestRunFailureInfo {
    return .with {
      $0.failureMessage = message
      $0.file = file
      $0.line = UInt64(line)
    }
  }
}
