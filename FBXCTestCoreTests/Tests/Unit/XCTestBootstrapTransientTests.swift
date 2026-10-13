/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBXCTestCore
import Foundation
import Testing

// MARK: - CodeCoverageConfiguration Tests

@Suite
struct CodeCoverageConfigurationTransientTests {

  @Test
  func descriptionContainsDirectory() {
    let config = CodeCoverageConfiguration(
      directory: "/my/dir",
      format: .exported,
      enableContinuousCoverageCollection: false
    )
    let desc = config.description
    #expect(desc.contains("/my/dir"), "Description should contain the coverage directory")
  }
}

// MARK: - TestManagerResultSummary Tests

@Suite
struct TestManagerResultSummaryTransientTests {

  @Test
  func statusForStatusString() {
    #expect(TestManagerResultSummary.status(forStatusString: "passed") == .passed)
    #expect(TestManagerResultSummary.status(forStatusString: "failed") == .failed)
    #expect(TestManagerResultSummary.status(forStatusString: "unknown") == .unknown)
    #expect(TestManagerResultSummary.status(forStatusString: "something-else") == .unknown)
    #expect(TestManagerResultSummary.status(forStatusString: "") == .unknown)
  }

  @Test
  func statusStringForStatus() {
    #expect(TestManagerResultSummary.statusString(for: .passed) == "Passed")
    #expect(TestManagerResultSummary.statusString(for: .failed) == "Failed")
    #expect(TestManagerResultSummary.statusString(for: .unknown) == "Unknown")
  }

  @Test
  func equality() {
    let date = Date(timeIntervalSince1970: 500)
    let summary1 = TestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    let summary2 = TestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    #expect(summary1 == summary2)
  }

  @Test
  func inequality() {
    let date = Date(timeIntervalSince1970: 500)
    let summary1 = TestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    let summary2 = TestManagerResultSummary(
      testSuite: "DifferentSuite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    #expect(summary1 != summary2)
  }

  @Test
  func inequalityByRunCount() {
    let date = Date(timeIntervalSince1970: 500)
    let summary1 = TestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 3, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    let summary2 = TestManagerResultSummary(
      testSuite: "Suite", finishTime: date, runCount: 99, failureCount: 1,
      unexpected: 0, testDuration: 2.0, totalDuration: 3.0
    )
    #expect(summary1 != summary2)
  }

  @Test
  func descriptionContainsSuiteName() {
    let summary = TestManagerResultSummary(
      testSuite: "DescSuite", finishTime: Date(), runCount: 1, failureCount: 0,
      unexpected: 0, testDuration: 1.0, totalDuration: 1.0
    )
    #expect(summary.description.contains("DescSuite"))
  }
}

@Suite
struct XCTestRunConfigurationTransientTests {

  // MARK: - ListTestConfiguration

  private func makeListConfig(
    env: [String: String] = [:],
    workDir: String = "/tmp",
    bundlePath: String = "/bundle.xctest",
    runnerAppPath: String? = nil,
    waitForDebugger: Bool = false,
    timeout: TimeInterval = 100,
    architectures: Set<String> = ["arm64"]
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

  @Test
  func listTestConfigurationTestType() {
    let config = makeListConfig()
    #expect(config.testType == XCTestType.listTest)
  }

  @Test
  func listTestConfigurationDescription() {
    let config = makeListConfig()
    let desc = config.description
    #expect(desc.contains("list-test"), "Description should contain test type")
    #expect(desc.contains("/bundle.xctest"), "Description should contain bundle path")
  }

  @Test
  func listTestConfigurationEquality() {
    let config1 = makeListConfig()
    let config2 = makeListConfig()
    #expect(config1 == config2)
    #expect(config1.hashValue == config2.hashValue)
  }

  // MARK: - TestManagerTestConfiguration

  @Test
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
    #expect(config.testType == XCTestType.applicationTest)
  }

  @Test
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
    #expect(config.testType == XCTestType.uiTest)
  }

  @Test
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
    #expect(desc.contains("ui-test"), "Description should contain test type")
    #expect(desc.contains("/runner.app"), "Description should contain runner path")
    #expect(desc.contains("/target.app"), "Description should contain target path")
    #expect(desc.contains("SomeFilter"), "Description should contain test filter")
  }

  // MARK: - LogicTestConfiguration

  @Test
  func logicTestConfigurationTestType() {
    let config = makeLogicConfig()
    #expect(config.testType == XCTestType.logicTest)
  }

  @Test
  func logicTestConfigurationDescription() {
    let config = makeLogicConfig(testFilter: "MyFilter")
    let desc = config.description
    #expect(desc.contains("logic-test"), "Description should contain test type")
    #expect(desc.contains("MyFilter"), "Description should contain test filter")
  }

  // MARK: - XCTestRunConfiguration

  @Test
  func buildEnvironmentWithEntries() {
    let config = makeListConfig()
    let env = config.buildEnvironment(withEntries: ["CUSTOM_KEY": "custom_value"])
    #expect(env["CUSTOM_KEY"] == "custom_value")
    #expect(env["XCTestConfigurationFilePath"] == nil)
  }

  @Test
  func configurationDefaultTimeout() {
    let config = makeListConfig(timeout: 0)
    #expect(config.testTimeout > 0)
  }

  @Test
  func configurationDescription() {
    let config = makeLogicConfig()
    let desc = config.description
    #expect(desc.contains("logic-test"), "Description should contain the test type")
    #expect(desc.contains("/logic.xctest"), "Description should contain the test bundle path")
  }
}

// MARK: - XCTestType Constants Tests

@Suite
struct XCTestTypeConstantsTransientTests {

  @Test
  func typeConstants() {
    #expect(XCTestType.applicationTest.rawValue == "application-test")
    #expect(XCTestType.logicTest.rawValue == "logic-test")
    #expect(XCTestType.listTest.rawValue == "list-test")
    #expect(XCTestType.uiTest.rawValue == "ui-test")
  }
}
