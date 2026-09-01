/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CompanionLib
@preconcurrency import FBControlCore
import Testing

@Suite
struct CompanionLibTransientTests {

  // MARK: - BridgeQueues Tests

  @Test
  func futureSerialFullfillmentQueueExists() {
    let queue = BridgeQueues.futureSerialFullfillmentQueue
    #expect((String(cString: __dispatch_queue_get_label(queue))) == ("com.facebook.fbfuture.fullfilment"))
  }

  @Test
  func miscEventReaderQueueExists() {
    let queue = BridgeQueues.miscEventReaderQueue
    #expect((String(cString: __dispatch_queue_get_label(queue))) == ("com.facebook.miscellaneous.reader"))
  }

  // MARK: - bridgeFBFuture (single future) Tests

  @Test
  func valueResolvesSuccessfulFuture() async throws {
    let expected = "hello" as NSString
    let future = FBFuture<NSString>(result: expected)
    let result = try await bridgeFBFuture(future)
    #expect((result) == (expected))
  }

  @Test
  func valueThrowsOnFailedFuture() async {
    let expectedError = NSError(domain: "test", code: 42)
    let future = FBFuture<NSString>(error: expectedError)
    do {
      _ = try await bridgeFBFuture(future)
      Issue.record("Expected error")
    } catch {
      let nsError = error as NSError
      #expect((nsError.domain) == ("test"))
      #expect((nsError.code) == (42))
    }
  }

  @Test
  func valueCancelsFutureOnTaskCancellation() async {
    let mutableFuture = FBMutableFuture<NSString>()
    let future = convertFBMutableFuture(mutableFuture)

    let task = Task {
      try await bridgeFBFuture(future)
    }

    // Give the continuation time to register
    try? await Task.sleep(nanoseconds: 50_000_000)
    task.cancel()

    // After cancellation the underlying future should have been cancelled
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect((task.isCancelled))
  }

  // MARK: - bridgeFBFutures (multiple futures) Tests

  @Test
  func valuesResolvesMultipleFuturesInOrder() async throws {
    let f1 = FBFuture<NSString>(result: "a" as NSString)
    let f2 = FBFuture<NSString>(result: "b" as NSString)
    let f3 = FBFuture<NSString>(result: "c" as NSString)

    let results = try await bridgeFBFutures([f1, f2, f3])
    #expect((results) == (["a" as NSString, "b" as NSString, "c" as NSString]))
  }

  @Test
  func valuesWithArrayResolvesInOrder() async throws {
    let futures = (0..<5).map { i in
      FBFuture<NSNumber>(result: NSNumber(value: i))
    }
    let results = try await bridgeFBFutures(futures)
    #expect((results.map(\.intValue)) == ([0, 1, 2, 3, 4]))
  }

  @Test
  func valuesThrowsIfAnyFutureFails() async {
    let f1 = FBFuture<NSString>(result: "ok" as NSString)
    let f2 = FBFuture<NSString>(error: NSError(domain: "test", code: 99))

    do {
      _ = try await bridgeFBFutures([f1, f2])
      Issue.record("Expected error")
    } catch {
      let nsError = error as NSError
      #expect((nsError.code) == (99))
    }
  }

  @Test
  func valuesWithEmptyArrayReturnsEmpty() async throws {
    let futures: [FBFuture<NSString>] = []
    let results = try await bridgeFBFutures(futures)
    #expect((results.isEmpty))
  }

  // MARK: - bridgeFBFutureVoid Tests

  @Test
  func awaitNSNullFuture() async throws {
    let future = FBFuture<NSNull>(result: NSNull())
    try await bridgeFBFutureVoid(future)
  }

  @Test
  func awaitNSNullFutureThrowsOnError() async {
    let future = FBFuture<NSNull>(error: NSError(domain: "test", code: 1))
    do {
      try await bridgeFBFutureVoid(future)
      Issue.record("Expected error")
    } catch {
      let nsError = error as NSError
      #expect((nsError.code) == (1))
    }
  }

  @Test
  func awaitAnyObjectFuture() async throws {
    let future = FBFuture<AnyObject>(result: "value" as NSString)
    try await bridgeFBFutureVoid(future)
  }

  // MARK: - bridgeFBFutureArray (NSArray bridge) Tests

  @Test
  func valueBridgesNSArrayToTypedSwiftArray() async throws {
    let nsArray = NSArray(array: [NSNumber(value: 1), NSNumber(value: 2), NSNumber(value: 3)])
    let future = FBFuture<NSArray>(result: nsArray)
    let result: [NSNumber] = try await bridgeFBFutureArray(future)
    #expect((result) == ([NSNumber(value: 1), NSNumber(value: 2), NSNumber(value: 3)]))
  }

  // MARK: - bridgeFBFutureDictionary (NSDictionary bridge) Tests

  @Test
  func valueBridgesNSDictionaryToTypedSwiftDict() async throws {
    let nsDict = NSDictionary(dictionary: ["key1": NSNumber(value: 10), "key2": NSNumber(value: 20)])
    let future = FBFuture<NSDictionary>(result: nsDict)
    let result: [NSString: NSNumber] = try await bridgeFBFutureDictionary(future)
    #expect((result["key1" as NSString]) == (NSNumber(value: 10)))
    #expect((result["key2" as NSString]) == (NSNumber(value: 20)))
  }

  // MARK: - convertFBMutableFuture Tests

  @Test
  func convertMutableFutureToFuture() async throws {
    let mutableFuture = FBMutableFuture<NSString>()
    let future = convertFBMutableFuture(mutableFuture)
    mutableFuture.resolve(withResult: "resolved" as NSString)
    let result = try await bridgeFBFuture(future)
    #expect((result) == ("resolved" as NSString))
  }

  @Test
  func convertMutableFutureToFutureWithError() async {
    let mutableFuture = FBMutableFuture<NSString>()
    let future = convertFBMutableFuture(mutableFuture)
    let expectedError = NSError(domain: "test", code: 77)
    mutableFuture.resolveWithError(expectedError)
    do {
      _ = try await bridgeFBFuture(future)
      Issue.record("Expected error")
    } catch {
      #expect(((error as NSError).code) == (77))
    }
  }

  // MARK: - FBCodeCoverageRequest Tests

  @Test
  func codeCoverageRequestInitSetsProperties() {
    let request = FBCodeCoverageRequest(collect: true, format: .exported, enableContinuousCoverageCollection: false)
    #expect((request.collect))
    #expect((request.format) == (.exported))
    #expect(!(request.shouldEnableContinuousCoverageCollection))
  }

  @Test
  func codeCoverageRequestNotCollecting() {
    let request = FBCodeCoverageRequest(collect: false, format: .raw, enableContinuousCoverageCollection: true)
    #expect(!(request.collect))
    #expect((request.format) == (.raw))
    #expect((request.shouldEnableContinuousCoverageCollection))
  }

  // MARK: - FBDsymInstallLinkToBundle Tests

  @Test
  func dsymInstallLinkToBundleXCTest() {
    let link = FBDsymInstallLinkToBundle(bundleID: "com.example.test", bundleType: .xcTest)
    #expect((link.bundleID) == ("com.example.test"))
    #expect((link.bundleType) == (.xcTest))
  }

  @Test
  func dsymInstallLinkToBundleApp() {
    let link = FBDsymInstallLinkToBundle(bundleID: "com.example.app", bundleType: .app)
    #expect((link.bundleID) == ("com.example.app"))
    #expect((link.bundleType) == (.app))
  }

  // MARK: - FBXCTestRunRequest Factory & Property Tests

  @Test
  func logicTestRequestProperties() {
    let coverageRequest = FBCodeCoverageRequest(collect: false, format: .raw, enableContinuousCoverageCollection: false)
    let request = FBXCTestRunRequest.logicTest(
      withTestBundleID: "com.test.bundle",
      environment: ["KEY": "VALUE"],
      arguments: ["-arg1"],
      testsToRun: Set(["TestClass/testMethod"]),
      testsToSkip: Set<String>(),
      testTimeout: NSNumber(value: 300),
      reportActivities: true,
      reportAttachments: false,
      coverageRequest: coverageRequest,
      collectLogs: true,
      waitForDebugger: false,
      collectResultBundle: false
    )
    #expect((request.isLogicTest))
    #expect(!(request.isUITest))
    #expect((request.testBundleID) == ("com.test.bundle"))
    #expect((request.environment) == (["KEY": "VALUE"]))
    #expect((request.arguments) == (["-arg1"]))
    #expect((request.testsToRun) == (Set(["TestClass/testMethod"])))
    #expect((request.testsToSkip.isEmpty))
    #expect((request.testTimeout) == (NSNumber(value: 300)))
    #expect((request.reportActivities))
    #expect(!(request.reportAttachments))
    #expect(!(request.coverageRequest.collect))
    #expect((request.collectLogs))
    #expect(!(request.waitForDebugger))
    #expect(!(request.collectResultBundle))
  }

  @Test
  func applicationTestRequestProperties() {
    let coverageRequest = FBCodeCoverageRequest(collect: true, format: .exported, enableContinuousCoverageCollection: true)
    let request = FBXCTestRunRequest.applicationTest(
      withTestBundleID: "com.test.apptest",
      testHostAppBundleID: "com.test.host",
      environment: [:],
      arguments: [],
      testsToRun: nil,
      testsToSkip: Set<String>(),
      testTimeout: NSNumber(value: 600),
      reportActivities: false,
      reportAttachments: true,
      coverageRequest: coverageRequest,
      collectLogs: false,
      waitForDebugger: true,
      collectResultBundle: true
    )
    #expect(!(request.isLogicTest))
    #expect(!(request.isUITest))
    #expect((request.testBundleID) == ("com.test.apptest"))
    #expect((request.testHostAppBundleID) == ("com.test.host"))
    #expect((request.testTargetAppBundleID) == nil)
    #expect((request.testsToRun) == nil)
    #expect((request.coverageRequest.collect))
    #expect((request.waitForDebugger))
    #expect((request.collectResultBundle))
  }

  @Test
  func uITestRequestProperties() {
    let coverageRequest = FBCodeCoverageRequest(collect: false, format: .raw, enableContinuousCoverageCollection: false)
    let request = FBXCTestRunRequest.uiTest(
      withTestBundleID: "com.test.uitest",
      testHostAppBundleID: "com.test.runner",
      testTargetAppBundleID: "com.test.app",
      environment: ["UI": "true"],
      arguments: ["-ui"],
      testsToRun: Set(["UITestSuite"]),
      testsToSkip: Set(["UITestSuite/testSkipped"]),
      testTimeout: NSNumber(value: 900),
      reportActivities: true,
      reportAttachments: true,
      coverageRequest: coverageRequest,
      collectLogs: true,
      collectResultBundle: false
    )
    #expect(!(request.isLogicTest))
    #expect((request.isUITest))
    #expect((request.testBundleID) == ("com.test.uitest"))
    #expect((request.testHostAppBundleID) == ("com.test.runner"))
    #expect((request.testTargetAppBundleID) == ("com.test.app"))
    #expect((request.environment) == (["UI": "true"]))
    #expect((request.arguments) == (["-ui"]))
    #expect((request.testsToRun) == (Set(["UITestSuite"])))
    #expect((request.testsToSkip) == (Set(["UITestSuite/testSkipped"])))
    #expect(!(request.waitForDebugger))
  }

  @Test
  func logicTestWithTestPathProperties() {
    let coverageRequest = FBCodeCoverageRequest(collect: false, format: .raw, enableContinuousCoverageCollection: false)
    let testURL = URL(fileURLWithPath: "/tmp/MyTest.xctest")
    let request = FBXCTestRunRequest.logicTest(
      withTestPath: testURL,
      environment: [:],
      arguments: [],
      testsToRun: nil,
      testsToSkip: Set<String>(),
      testTimeout: NSNumber(value: 60),
      reportActivities: false,
      reportAttachments: false,
      coverageRequest: coverageRequest,
      collectLogs: false,
      waitForDebugger: false,
      collectResultBundle: false
    )
    #expect((request.isLogicTest))
    #expect(!(request.isUITest))
    #expect((request.testPath) == (testURL))
  }

  // MARK: - FBXCTestReporterConfiguration Tests

  @Test
  func reporterConfigurationInitSetsProperties() {
    let config = FBXCTestReporterConfiguration(
      resultBundlePath: "/path/to/result",
      coverageConfiguration: nil,
      logDirectoryPath: "/path/to/logs",
      binariesPaths: ["/path/to/binary1", "/path/to/binary2"],
      reportAttachments: true,
      reportResultBundle: false
    )
    #expect((config.resultBundlePath) == ("/path/to/result"))
    #expect((config.coverageConfiguration) == nil)
    #expect((config.logDirectoryPath) == ("/path/to/logs"))
    #expect((config.binariesPaths) == (["/path/to/binary1", "/path/to/binary2"]))
    #expect((config.reportAttachments))
    #expect(!(config.reportResultBundle))
  }

  @Test
  func reporterConfigurationNilPaths() {
    let config = FBXCTestReporterConfiguration(
      resultBundlePath: nil,
      coverageConfiguration: nil,
      logDirectoryPath: nil,
      binariesPaths: [],
      reportAttachments: false,
      reportResultBundle: true
    )
    #expect((config.resultBundlePath) == nil)
    #expect((config.logDirectoryPath) == nil)
    #expect((config.binariesPaths.isEmpty))
    #expect(!(config.reportAttachments))
    #expect((config.reportResultBundle))
  }

  @Test
  func reporterConfigurationDescription() {
    let config = FBXCTestReporterConfiguration(
      resultBundlePath: "/result",
      coverageConfiguration: nil,
      logDirectoryPath: "/logs",
      binariesPaths: ["/bin"],
      reportAttachments: true,
      reportResultBundle: false
    )
    let desc = config.description
    #expect((desc.contains("/result")))
    #expect((desc.contains("/logs")))
  }

  // MARK: - bridgeFBFuture with delayed resolution Tests

  @Test
  func valueWithDelayedResolution() async throws {
    let mutableFuture = FBMutableFuture<NSString>()
    let future = convertFBMutableFuture(mutableFuture)

    // Resolve after a short delay
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
      mutableFuture.resolve(withResult: "delayed" as NSString)
    }

    let result = try await bridgeFBFuture(future)
    #expect((result) == ("delayed" as NSString))
  }

  @Test
  func valuesWithDelayedResolution() async throws {
    let mf1 = FBMutableFuture<NSNumber>()
    let mf2 = FBMutableFuture<NSNumber>()
    let f1 = convertFBMutableFuture(mf1)
    let f2 = convertFBMutableFuture(mf2)

    // Resolve in reverse order to verify ordering is preserved
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
      mf1.resolve(withResult: NSNumber(value: 1))
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
      mf2.resolve(withResult: NSNumber(value: 2))
    }

    let results = try await bridgeFBFutures([f1, f2])
    #expect((results[0]) == (NSNumber(value: 1)))
    #expect((results[1]) == (NSNumber(value: 2)))
  }
}
