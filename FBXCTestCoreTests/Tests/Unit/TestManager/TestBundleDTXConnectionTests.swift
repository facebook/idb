/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBXCTestCore
import XCTest

/// Records the bundle callbacks the connection forwards to the IDE interface.
private final class RecordingIDEInterface: NSObject {
  private(set) var calls: [String] = []

  @objc(_XCT_testBundleReadyWithProtocolVersion:minimumVersion:)
  func testBundleReady(protocolVersion: NSNumber, minimumVersion: NSNumber) -> Any? {
    calls.append("bundleReady:\(protocolVersion):\(minimumVersion)")
    return nil
  }

  @objc(_XCT_didFinishExecutingTestPlan)
  func didFinishExecutingTestPlan() -> Any? {
    calls.append("didFinishExecutingTestPlan")
    return nil
  }

  @objc(_XCT_logDebugMessage:)
  func logDebugMessage(_ message: NSString) -> Any? {
    calls.append("logDebugMessage:\(message)")
    return nil
  }
}

/// The callbacks a test bundle makes over the proxy channel, and what each does to the waits the
/// connection's driver awaits. The bundle side is reached by invoking the callbacks directly; the
/// DTX transport itself is not exercised.
final class TestBundleDTXConnectionTests: XCTestCase {

  private let interface = RecordingIDEInterface()
  private let events = TestBundleEvents()

  private func makeConnection(socket: Int32 = -1) throws -> TestBundleDTXConnection {
    let sessionIdentifier = UUID()
    let testConfiguration = try TestConfiguration(
      byWritingToFileWithSessionIdentifier: sessionIdentifier,
      moduleName: "ModuleName",
      testBundlePath: NSTemporaryDirectory(),
      uiTesting: false,
      testsToRun: nil,
      testsToSkip: nil,
      targetApplicationPath: nil,
      targetApplicationBundleID: nil,
      testApplicationDependencies: nil,
      automationFrameworkPath: nil,
      reportActivities: false)
    let context = TestManagerContext(
      sessionIdentifier: sessionIdentifier,
      timeout: 60,
      testHostLaunchConfiguration: ApplicationLaunchConfiguration(
        bundleID: "com.example.host",
        bundleName: "Host",
        arguments: [],
        environment: [:],
        waitForDebugger: false,
        launchMode: .failIfRunning),
      testedApplicationAdditionalEnvironment: [:],
      testConfiguration: testConfiguration)
    return TestBundleDTXConnection(
      context: context,
      work: DispatchQueue(label: "com.facebook.xctestbootstrap.tests.work"),
      socket: socket,
      interface: interface,
      delegate: events,
      request: DispatchQueue(label: "com.facebook.xctestbootstrap.tests.request"),
      logger: ControlCoreLoggerSink(ControlCoreGlobalConfiguration.defaultLogger))
  }

  private func bundleReady(_ connection: TestBundleDTXConnection, protocolVersion: Int, minimumVersion: Int) {
    _ = connection.perform(
      NSSelectorFromString("_XCT_testBundleReadyWithProtocolVersion:minimumVersion:"),
      with: NSNumber(value: protocolVersion),
      with: NSNumber(value: minimumVersion))
  }

  private struct BundleBecameReady: Error {}

  private func bundleReadyError() async throws -> NSError {
    do {
      try await events.bundleReady.wait()
    } catch {
      return error as NSError
    }
    throw BundleBecameReady()
  }

  private func assertBundleReadyFails(describing expected: String, file: StaticString = #filePath, line: UInt = #line) async {
    do {
      try await events.bundleReady.wait()
      XCTFail("Waiting for the bundle should fail", file: file, line: line)
    } catch {
      XCTAssertTrue(
        error.localizedDescription.contains(expected),
        "\(error.localizedDescription) should contain \(expected)",
        file: file,
        line: line)
    }
  }

  private func isFinished(_ outcome: TestPlanOutcome) -> Bool {
    guard case .finished = outcome else {
      return false
    }
    return true
  }

  private func isFailed(_ outcome: TestPlanOutcome, describing expected: String) -> Bool {
    guard case let .failed(error) = outcome else {
      return false
    }
    return error.localizedDescription.contains(expected)
  }

  private func isUnfinished(_ outcome: TestPlanOutcome) -> Bool {
    guard case .unfinished = outcome else {
      return false
    }
    return true
  }

  // MARK: - Bundle readiness

  func testABundleOnACompatibleProtocolIsReadyAndForwarded() async throws {
    let connection = try makeConnection()

    bundleReady(connection, protocolVersion: 36, minimumVersion: 8)

    try await events.bundleReady.wait()
    XCTAssertEqual(interface.calls, ["bundleReady:36:8"])
  }

  func testABundleRequiringANewerProtocolFailsTheWaitWithoutForwarding() async throws {
    let connection = try makeConnection()

    bundleReady(connection, protocolVersion: 40, minimumVersion: 37)

    await assertBundleReadyFails(describing: "test process requires at least version 37, IDE is running version 36")
    XCTAssertEqual(interface.calls, [])
  }

  func testABundleOnAnOlderProtocolFailsTheWaitWithoutForwarding() async throws {
    let connection = try makeConnection()

    bundleReady(connection, protocolVersion: 7, minimumVersion: 1)

    await assertBundleReadyFails(describing: "IDE requires at least version 8, test process is running version 7")
    XCTAssertEqual(interface.calls, [])
  }

  func testAProtocolMismatchIsAStartupFailure() async throws {
    let connection = try makeConnection()

    bundleReady(connection, protocolVersion: 40, minimumVersion: 37)

    let error = try await bundleReadyError()
    XCTAssertEqual(error.domain, XCTestBootstrapErrorDomain)
    XCTAssertEqual(error.code, XCTestBootstrapErrorCode.startupFailure.rawValue)
  }

  func testARunnerReportingReadyMakesTheBundleReady() async throws {
    let connection = try makeConnection()

    _ = connection.perform(NSSelectorFromString("_XCT_testRunnerReadyWithCapabilities:"), with: nil)

    try await events.bundleReady.wait()
  }

  func testUITestingFailingToInitializeFailsTheWait() async throws {
    let connection = try makeConnection()

    _ = connection.perform(
      NSSelectorFromString("_XCT_initializationForUITestingDidFailWithError:"),
      with: NSError(domain: "com.example.xctest", code: 3))

    await assertBundleReadyFails(describing: "Failed to initialize for UI testing")
  }

  func testUITestingFailingToInitializeIsAStartupFailureCausedByTheRunnersError() async throws {
    let connection = try makeConnection()

    _ = connection.perform(
      NSSelectorFromString("_XCT_initializationForUITestingDidFailWithError:"),
      with: NSError(domain: "com.example.xctest", code: 3))

    let error = try await bundleReadyError()
    XCTAssertEqual(error.domain, XCTestBootstrapErrorDomain)
    XCTAssertEqual(error.code, XCTestBootstrapErrorCode.startupFailure.rawValue)
    let cause = try XCTUnwrap(error.userInfo[NSUnderlyingErrorKey] as? NSError)
    XCTAssertEqual(cause.domain, "com.example.xctest")
    XCTAssertEqual(cause.code, 3)
  }

  // MARK: - Connection

  /// `XCTestRunMethodHandler` treats `TestFailureErrorDomain` as the test process failing, not idb.
  func testWrappingADeadSocketFailsInTheTestErrorDomain() throws {
    let connection = try makeConnection()

    XCTAssertThrowsError(try connection.connect()) { error in
      XCTAssertEqual((error as NSError).domain, TestFailureErrorDomain)
    }
  }

  /// DTX raises when the object a channel exports does not conform to the channel's exported
  /// interface, so starting a session over a live connection would end the process.
  func testStartingASessionExportsTheConnectionAsEachInterfaceItConformsTo() throws {
    // xcodebuild's test runner has already loaded DTXConnectionServices, from its own Xcode, which
    // the loader rejects when it is not the developer directory the loader checks against.
    if objc_lookUpClass("DTXConnection") == nil {
      try XCTestBootstrapFrameworkLoader.allDependentFrameworks.loadPrivateFrameworks(nil)
    }
    var sockets: [Int32] = [-1, -1]
    XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets), 0)
    // The connection owns the other end once wrapped.
    defer { close(sockets[1]) }
    let connection = try makeConnection(socket: sockets[0])
    try connection.connect()
    defer { connection.disconnect() }

    connection.setupAndStartSession()

    for name in ["XCTestManager_IDEInterface", "XCTMessagingChannel_DaemonToIDE", "XCTMessagingChannel_RunnerToIDE"] {
      XCTAssertTrue(connection.conforms(to: try XCTUnwrap(objc_getProtocol(name))), name)
    }
  }

  // MARK: - Test plan

  func testFinishingTheTestPlanCompletesItAndIsForwarded() throws {
    let connection = try makeConnection()
    XCTAssertTrue(isUnfinished(events.testPlanOutcome))

    _ = connection.perform(NSSelectorFromString("_XCT_didFinishExecutingTestPlan"))

    XCTAssertTrue(isFinished(events.testPlanOutcome))
    XCTAssertEqual(interface.calls, ["didFinishExecutingTestPlan"])
  }

  func testUITestingFailingToInitializeAlsoFailsTheTestPlan() throws {
    let connection = try makeConnection()

    _ = connection.perform(
      NSSelectorFromString("_XCT_initializationForUITestingDidFailWithError:"),
      with: NSError(domain: "com.example.xctest", code: 3))

    XCTAssertTrue(isFailed(events.testPlanOutcome, describing: "Failed to initialize for UI testing"))
  }

  func testUITestingFailingToInitializeAfterTheBundleIsReadyEndsTheTestPlan() async throws {
    let connection = try makeConnection()
    bundleReady(connection, protocolVersion: 36, minimumVersion: 8)
    try await events.bundleReady.wait()

    _ = connection.perform(
      NSSelectorFromString("_XCT_initializationForUITestingDidFailWithError:"),
      with: NSError(domain: "com.example.xctest", code: 3))

    XCTAssertTrue(isFailed(events.testPlanOutcome, describing: "Failed to initialize for UI testing"))
  }

  // MARK: - Forwarding

  func testOtherCallbacksAreForwardedToTheInterface() throws {
    let connection = try makeConnection()

    _ = connection.perform(NSSelectorFromString("_XCT_logDebugMessage:"), with: "hello" as NSString)

    XCTAssertEqual(interface.calls, ["logDebugMessage:hello"])
  }
}
