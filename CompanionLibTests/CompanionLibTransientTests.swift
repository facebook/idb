/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CompanionLib
@preconcurrency import FBControlCore
import XCTest

final class CompanionLibTransientTests: XCTestCase {

  // MARK: - BridgeQueues Tests

  func testFutureSerialFullfillmentQueueExists() {
    let queue = BridgeQueues.futureSerialFullfillmentQueue
    XCTAssertEqual(String(cString: __dispatch_queue_get_label(queue)), "com.facebook.fbfuture.fullfilment")
  }

  func testMiscEventReaderQueueExists() {
    let queue = BridgeQueues.miscEventReaderQueue
    XCTAssertEqual(String(cString: __dispatch_queue_get_label(queue)), "com.facebook.miscellaneous.reader")
  }

  // MARK: - BridgeFuture.value (single future) Tests

  func testValueResolvesSuccessfulFuture() async throws {
    let expected = "hello" as NSString
    let future = FBFuture<NSString>(result: expected)
    let result = try await BridgeFuture.value(future)
    XCTAssertEqual(result, expected)
  }

  func testValueThrowsOnFailedFuture() async {
    let expectedError = NSError(domain: "test", code: 42)
    let future = FBFuture<NSString>(error: expectedError)
    do {
      _ = try await BridgeFuture.value(future)
      XCTFail("Expected error")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, "test")
      XCTAssertEqual(nsError.code, 42)
    }
  }

  func testValueCancelsFutureOnTaskCancellation() async {
    let mutableFuture = FBMutableFuture<NSString>()
    let future = BridgeFuture.convertToFuture(mutableFuture)

    let task = Task {
      try await BridgeFuture.value(future)
    }

    // Give the continuation time to register
    try? await Task.sleep(nanoseconds: 50_000_000)
    task.cancel()

    // After cancellation the underlying future should have been cancelled
    try? await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(task.isCancelled)
  }

  // MARK: - BridgeFuture.values (multiple futures) Tests

  func testValuesResolvesMultipleFuturesInOrder() async throws {
    let f1 = FBFuture<NSString>(result: "a" as NSString)
    let f2 = FBFuture<NSString>(result: "b" as NSString)
    let f3 = FBFuture<NSString>(result: "c" as NSString)

    let results = try await BridgeFuture.values(f1, f2, f3)
    XCTAssertEqual(results, ["a" as NSString, "b" as NSString, "c" as NSString])
  }

  func testValuesWithArrayResolvesInOrder() async throws {
    let futures = (0..<5).map { i in
      FBFuture<NSNumber>(result: NSNumber(value: i))
    }
    let results = try await BridgeFuture.values(futures)
    XCTAssertEqual(results.map(\.intValue), [0, 1, 2, 3, 4])
  }

  func testValuesThrowsIfAnyFutureFails() async {
    let f1 = FBFuture<NSString>(result: "ok" as NSString)
    let f2 = FBFuture<NSString>(error: NSError(domain: "test", code: 99))

    do {
      _ = try await BridgeFuture.values([f1, f2])
      XCTFail("Expected error")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.code, 99)
    }
  }

  func testValuesWithEmptyArrayReturnsEmpty() async throws {
    let futures: [FBFuture<NSString>] = []
    let results = try await BridgeFuture.values(futures)
    XCTAssertTrue(results.isEmpty)
  }

  // MARK: - BridgeFuture.await Tests

  func testAwaitNSNullFuture() async throws {
    let future = FBFuture<NSNull>(result: NSNull())
    try await BridgeFuture.await(future)
  }

  func testAwaitNSNullFutureThrowsOnError() async {
    let future = FBFuture<NSNull>(error: NSError(domain: "test", code: 1))
    do {
      try await BridgeFuture.await(future)
      XCTFail("Expected error")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.code, 1)
    }
  }

  func testAwaitAnyObjectFuture() async throws {
    let future = FBFuture<AnyObject>(result: "value" as NSString)
    try await BridgeFuture.await(future)
  }

  // MARK: - BridgeFuture.value (NSArray bridge) Tests

  func testValueBridgesNSArrayToTypedSwiftArray() async throws {
    let nsArray = NSArray(array: [NSNumber(value: 1), NSNumber(value: 2), NSNumber(value: 3)])
    let future = FBFuture<NSArray>(result: nsArray)
    let result: [NSNumber] = try await BridgeFuture.value(future)
    XCTAssertEqual(result, [NSNumber(value: 1), NSNumber(value: 2), NSNumber(value: 3)])
  }

  // MARK: - BridgeFuture.value (NSDictionary bridge) Tests

  func testValueBridgesNSDictionaryToTypedSwiftDict() async throws {
    let nsDict = NSDictionary(dictionary: ["key1": NSNumber(value: 10), "key2": NSNumber(value: 20)])
    let future = FBFuture<NSDictionary>(result: nsDict)
    let result: [NSString: NSNumber] = try await BridgeFuture.value(future)
    XCTAssertEqual(result["key1" as NSString], NSNumber(value: 10))
    XCTAssertEqual(result["key2" as NSString], NSNumber(value: 20))
  }

  // MARK: - BridgeFuture.convertToFuture Tests

  func testConvertMutableFutureToFuture() async throws {
    let mutableFuture = FBMutableFuture<NSString>()
    let future = BridgeFuture.convertToFuture(mutableFuture)
    mutableFuture.resolve(withResult: "resolved" as NSString)
    let result = try await BridgeFuture.value(future)
    XCTAssertEqual(result, "resolved" as NSString)
  }

  func testConvertMutableFutureToFutureWithError() async {
    let mutableFuture = FBMutableFuture<NSString>()
    let future = BridgeFuture.convertToFuture(mutableFuture)
    let expectedError = NSError(domain: "test", code: 77)
    mutableFuture.resolveWithError(expectedError)
    do {
      _ = try await BridgeFuture.value(future)
      XCTFail("Expected error")
    } catch {
      XCTAssertEqual((error as NSError).code, 77)
    }
  }

  // MARK: - FBCodeCoverageRequest Tests

  func testCodeCoverageRequestInitSetsProperties() {
    let request = FBCodeCoverageRequest(collect: true, format: .exported, enableContinuousCoverageCollection: false)
    XCTAssertTrue(request.collect)
    XCTAssertEqual(request.format, .exported)
    XCTAssertFalse(request.shouldEnableContinuousCoverageCollection)
  }

  func testCodeCoverageRequestNotCollecting() {
    let request = FBCodeCoverageRequest(collect: false, format: .raw, enableContinuousCoverageCollection: true)
    XCTAssertFalse(request.collect)
    XCTAssertEqual(request.format, .raw)
    XCTAssertTrue(request.shouldEnableContinuousCoverageCollection)
  }

  // MARK: - FBDsymInstallLinkToBundle Tests

  func testDsymInstallLinkToBundleXCTest() {
    let link = FBDsymInstallLinkToBundle("com.example.test", bundle_type: .xcTest)
    XCTAssertEqual(link.bundle_id, "com.example.test")
    XCTAssertEqual(link.bundle_type, .xcTest)
  }

  func testDsymInstallLinkToBundleApp() {
    let link = FBDsymInstallLinkToBundle("com.example.app", bundle_type: .app)
    XCTAssertEqual(link.bundle_id, "com.example.app")
    XCTAssertEqual(link.bundle_type, .app)
  }

  // MARK: - FBXCTestRunRequest Factory & Property Tests

  func testLogicTestRequestProperties() {
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
    XCTAssertTrue(request.isLogicTest)
    XCTAssertFalse(request.isUITest)
    XCTAssertEqual(request.testBundleID, "com.test.bundle")
    XCTAssertEqual(request.environment, ["KEY": "VALUE"])
    XCTAssertEqual(request.arguments, ["-arg1"])
    XCTAssertEqual(request.testsToRun, Set(["TestClass/testMethod"]))
    XCTAssertTrue(request.testsToSkip.isEmpty)
    XCTAssertEqual(request.testTimeout, NSNumber(value: 300))
    XCTAssertTrue(request.reportActivities)
    XCTAssertFalse(request.reportAttachments)
    XCTAssertFalse(request.coverageRequest.collect)
    XCTAssertTrue(request.collectLogs)
    XCTAssertFalse(request.waitForDebugger)
    XCTAssertFalse(request.collectResultBundle)
  }

  func testApplicationTestRequestProperties() {
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
    XCTAssertFalse(request.isLogicTest)
    XCTAssertFalse(request.isUITest)
    XCTAssertEqual(request.testBundleID, "com.test.apptest")
    XCTAssertEqual(request.testHostAppBundleID, "com.test.host")
    XCTAssertNil(request.testTargetAppBundleID)
    XCTAssertNil(request.testsToRun)
    XCTAssertTrue(request.coverageRequest.collect)
    XCTAssertTrue(request.waitForDebugger)
    XCTAssertTrue(request.collectResultBundle)
  }

  func testUITestRequestProperties() {
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
    XCTAssertFalse(request.isLogicTest)
    XCTAssertTrue(request.isUITest)
    XCTAssertEqual(request.testBundleID, "com.test.uitest")
    XCTAssertEqual(request.testHostAppBundleID, "com.test.runner")
    XCTAssertEqual(request.testTargetAppBundleID, "com.test.app")
    XCTAssertEqual(request.environment, ["UI": "true"])
    XCTAssertEqual(request.arguments, ["-ui"])
    XCTAssertEqual(request.testsToRun, Set(["UITestSuite"]))
    XCTAssertEqual(request.testsToSkip, Set(["UITestSuite/testSkipped"]))
    XCTAssertFalse(request.waitForDebugger)
  }

  func testLogicTestWithTestPathProperties() {
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
    XCTAssertTrue(request.isLogicTest)
    XCTAssertFalse(request.isUITest)
    XCTAssertEqual(request.testPath, testURL)
  }

  // MARK: - FBXCTestReporterConfiguration Tests

  func testReporterConfigurationInitSetsProperties() {
    let config = FBXCTestReporterConfiguration(
      resultBundlePath: "/path/to/result",
      coverageConfiguration: nil,
      logDirectoryPath: "/path/to/logs",
      binariesPaths: ["/path/to/binary1", "/path/to/binary2"],
      reportAttachments: true,
      reportResultBundle: false
    )
    XCTAssertEqual(config.resultBundlePath, "/path/to/result")
    XCTAssertNil(config.coverageConfiguration)
    XCTAssertEqual(config.logDirectoryPath, "/path/to/logs")
    XCTAssertEqual(config.binariesPaths, ["/path/to/binary1", "/path/to/binary2"])
    XCTAssertTrue(config.reportAttachments)
    XCTAssertFalse(config.reportResultBundle)
  }

  func testReporterConfigurationNilPaths() {
    let config = FBXCTestReporterConfiguration(
      resultBundlePath: nil,
      coverageConfiguration: nil,
      logDirectoryPath: nil,
      binariesPaths: [],
      reportAttachments: false,
      reportResultBundle: true
    )
    XCTAssertNil(config.resultBundlePath)
    XCTAssertNil(config.logDirectoryPath)
    XCTAssertTrue(config.binariesPaths.isEmpty)
    XCTAssertFalse(config.reportAttachments)
    XCTAssertTrue(config.reportResultBundle)
  }

  func testReporterConfigurationDescription() {
    let config = FBXCTestReporterConfiguration(
      resultBundlePath: "/result",
      coverageConfiguration: nil,
      logDirectoryPath: "/logs",
      binariesPaths: ["/bin"],
      reportAttachments: true,
      reportResultBundle: false
    )
    let desc = config.description
    XCTAssertTrue(desc.contains("/result"))
    XCTAssertTrue(desc.contains("/logs"))
  }

  // MARK: - FBIDBError Tests

  func testIDBErrorDomainConstant() {
    XCTAssertEqual(FBIDBErrorDomain, "com.facebook.idb")
  }

  // MARK: - BridgeFuture with delayed resolution Tests

  func testValueWithDelayedResolution() async throws {
    let mutableFuture = FBMutableFuture<NSString>()
    let future = BridgeFuture.convertToFuture(mutableFuture)

    // Resolve after a short delay
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
      mutableFuture.resolve(withResult: "delayed" as NSString)
    }

    let result = try await BridgeFuture.value(future)
    XCTAssertEqual(result, "delayed" as NSString)
  }

  func testValuesWithDelayedResolution() async throws {
    let mf1 = FBMutableFuture<NSNumber>()
    let mf2 = FBMutableFuture<NSNumber>()
    let f1 = BridgeFuture.convertToFuture(mf1)
    let f2 = BridgeFuture.convertToFuture(mf2)

    // Resolve in reverse order to verify ordering is preserved
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
      mf1.resolve(withResult: NSNumber(value: 1))
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
      mf2.resolve(withResult: NSNumber(value: 2))
    }

    let results = try await BridgeFuture.values([f1, f2])
    XCTAssertEqual(results[0], NSNumber(value: 1))
    XCTAssertEqual(results[1], NSNumber(value: 2))
  }
}
