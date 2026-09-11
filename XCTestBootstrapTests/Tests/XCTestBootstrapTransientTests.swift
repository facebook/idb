/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import XCTestBootstrap

// MARK: - CodeCoverageConfiguration Tests

final class CodeCoverageConfigurationTransientTests: XCTestCase {

  func testDescriptionContainsDirectory() {
    let config = CodeCoverageConfiguration(
      directory: "/my/dir",
      format: .exported,
      enableContinuousCoverageCollection: false
    )
    let desc = config.description
    XCTAssertTrue(desc.contains("/my/dir"), "Description should contain the coverage directory")
  }
}

// MARK: - TestManagerResultSummary Tests

final class TestManagerResultSummaryTransientTests: XCTestCase {

  func testStatusForStatusString() {
    XCTAssertEqual(TestManagerResultSummary.status(forStatusString: "passed"), .passed)
    XCTAssertEqual(TestManagerResultSummary.status(forStatusString: "failed"), .failed)
    XCTAssertEqual(TestManagerResultSummary.status(forStatusString: "unknown"), .unknown)
    XCTAssertEqual(TestManagerResultSummary.status(forStatusString: "something-else"), .unknown)
    XCTAssertEqual(TestManagerResultSummary.status(forStatusString: ""), .unknown)
  }

  func testStatusStringForStatus() {
    XCTAssertEqual(TestManagerResultSummary.statusString(for: .passed), "Passed")
    XCTAssertEqual(TestManagerResultSummary.statusString(for: .failed), "Failed")
    XCTAssertEqual(TestManagerResultSummary.statusString(for: .unknown), "Unknown")
  }

  func testEquality() {
    let date = Date(timeIntervalSince1970: 500)
    let summary1 = TestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    let summary2 = TestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    XCTAssertEqual(summary1, summary2)
  }

  func testInequality() {
    let date = Date(timeIntervalSince1970: 500)
    let summary1 = TestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    let summary2 = TestManagerResultSummary(
      testSuite: "DifferentSuite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    XCTAssertNotEqual(summary1, summary2)
  }

  func testInequalityByRunCount() {
    let date = Date(timeIntervalSince1970: 500)
    let summary1 = TestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    let summary2 = TestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 99, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    XCTAssertNotEqual(summary1, summary2)
  }

  func testDescriptionContainsSuiteName() {
    let summary = TestManagerResultSummary(
      testSuite: "DescSuite", finishTime: Date(), runCount: 1, failureCount: 0,
      unexpected: 0, testDuration: 1.0, totalDuration: 1.0
    )
    XCTAssertTrue(summary.description.contains("DescSuite"))
  }
}

final class FBXCTestConfigurationTransientTests: XCTestCase {

  // MARK: - ListTestConfiguration

  private func makeListConfig(
    env: [String: String] = [:],
    workDir: String = "/tmp",
    bundlePath: String = "/bundle.xctest",
    runnerAppPath: String? = nil,
    waitForDebugger: Bool = false,
    timeout: TimeInterval = 100,
    architectures: Set<String> = ["x86_64"]
  ) -> ListTestConfiguration {
    return ListTestConfiguration(
      environment: env,
      workingDirectory: workDir,
      testBundlePath: bundlePath,
      runnerAppPath: runnerAppPath,
      waitForDebugger: waitForDebugger,
      timeout: timeout,
      architectures: architectures
    )
  }

  private func makeLogicConfig(
    env: [String: String] = [:],
    workDir: String = "/tmp",
    bundlePath: String = "/logic.xctest",
    waitForDebugger: Bool = false,
    timeout: TimeInterval = 100,
    testFilter: String? = nil,
    mirroring: LogicTestMirrorLogs = [],
    coverageConfiguration: CodeCoverageConfiguration? = nil,
    binaryPath: String? = nil,
    logDirectoryPath: String? = nil,
    architectures: Set<String> = ["arm64"]
  ) -> LogicTestConfiguration {
    return LogicTestConfiguration(
      environment: env,
      workingDirectory: workDir,
      testBundlePath: bundlePath,
      waitForDebugger: waitForDebugger,
      timeout: timeout,
      testFilter: testFilter,
      mirroring: mirroring,
      coverageConfiguration: coverageConfiguration,
      binaryPath: binaryPath,
      logDirectoryPath: logDirectoryPath,
      architectures: architectures
    )
  }

  func testListTestConfigurationTestType() {
    let config = makeListConfig()
    XCTAssertEqual(config.testType, XCTestType.listTest)
  }

  func testListTestConfigurationDescription() {
    let config = makeListConfig()
    let desc = config.description
    XCTAssertTrue(desc.contains("list-test"), "Description should contain test type")
    XCTAssertTrue(desc.contains("/bundle.xctest"), "Description should contain bundle path")
  }

  func testListTestConfigurationEquality() {
    let config1 = makeListConfig()
    let config2 = makeListConfig()
    XCTAssertEqual(config1, config2)
    XCTAssertEqual(config1.hash, config2.hash)
  }

  // MARK: - TestManagerTestConfiguration

  func testManagerTestConfigurationApplicationTestType() {
    let config = TestManagerTestConfiguration(
      environment: [:],
      workingDirectory: "/tmp",
      testBundlePath: "/test.xctest",
      waitForDebugger: false,
      timeout: 300,
      runnerAppPath: "/runner.app",
      testTargetAppPath: nil,
      testFilter: nil,
      videoRecordingPath: nil,
      testArtifactsFilenameGlobs: nil,
      osLogPath: nil
    )
    XCTAssertEqual(config.testType, XCTestType.applicationTest)
  }

  func testManagerTestConfigurationUITestType() {
    let config = TestManagerTestConfiguration(
      environment: [:],
      workingDirectory: "/tmp",
      testBundlePath: "/test.xctest",
      waitForDebugger: false,
      timeout: 300,
      runnerAppPath: "/runner.app",
      testTargetAppPath: "/target.app",
      testFilter: nil,
      videoRecordingPath: nil,
      testArtifactsFilenameGlobs: nil,
      osLogPath: nil
    )
    XCTAssertEqual(config.testType, XCTestType.uiTest)
  }

  func testManagerTestConfigurationDescription() {
    let config = TestManagerTestConfiguration(
      environment: [:],
      workingDirectory: "/tmp",
      testBundlePath: "/test.xctest",
      waitForDebugger: false,
      timeout: 300,
      runnerAppPath: "/runner.app",
      testTargetAppPath: "/target.app",
      testFilter: "SomeFilter",
      videoRecordingPath: "/vid.mp4",
      testArtifactsFilenameGlobs: nil,
      osLogPath: nil
    )
    let desc = config.description
    XCTAssertTrue(desc.contains("ui-test"), "Description should contain test type")
    XCTAssertTrue(desc.contains("/runner.app"), "Description should contain runner path")
    XCTAssertTrue(desc.contains("/target.app"), "Description should contain target path")
    XCTAssertTrue(desc.contains("SomeFilter"), "Description should contain test filter")
  }

  // MARK: - LogicTestConfiguration

  func testLogicTestConfigurationTestType() {
    let config = makeLogicConfig()
    XCTAssertEqual(config.testType, XCTestType.logicTest)
  }

  func testLogicTestConfigurationDescription() {
    let config = makeLogicConfig(testFilter: "MyFilter")
    let desc = config.description
    XCTAssertTrue(desc.contains("logic-test"), "Description should contain test type")
    XCTAssertTrue(desc.contains("MyFilter"), "Description should contain test filter")
  }

  // MARK: - FBXCTestConfiguration base class

  func testBuildEnvironmentWithEntries() {
    let config = makeListConfig()
    let env = config.buildEnvironment(withEntries: ["CUSTOM_KEY": "custom_value"])
    XCTAssertEqual(env["CUSTOM_KEY"], "custom_value")
    XCTAssertNil(env["XCTestConfigurationFilePath"])
  }

  func testConfigurationDefaultTimeout() {
    let config = makeListConfig(timeout: 0)
    XCTAssertGreaterThan(config.testTimeout, 0)
  }

  func testConfigurationCopy() {
    let config = makeListConfig()
    let copied = config.copy() as! ListTestConfiguration
    XCTAssertEqual(config, copied)
  }

  func testConfigurationInequalityAcrossSubclasses() {
    let listConfig = makeListConfig()
    let logicConfig = makeLogicConfig(architectures: ["x86_64"])
    XCTAssertFalse(listConfig.isEqual(logicConfig))
  }

  func testConfigurationDescription() {
    let config = makeLogicConfig()
    let desc = config.description
    XCTAssertTrue(desc.contains("logic-test"), "Description should contain the test type")
    XCTAssertTrue(desc.contains("/logic.xctest"), "Description should contain the test bundle path")
  }
}

// MARK: - XCTestType Constants Tests

final class XCTestTypeConstantsTransientTests: XCTestCase {

  func testTypeConstants() {
    XCTAssertEqual(XCTestType.applicationTest.rawValue, "application-test")
    XCTAssertEqual(XCTestType.logicTest.rawValue, "logic-test")
    XCTAssertEqual(XCTestType.listTest.rawValue, "list-test")
    XCTAssertEqual(XCTestType.uiTest.rawValue, "ui-test")
  }
}
