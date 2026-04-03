/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

// MARK: JSON Keys

private let KeyEnvironment = "environment"
private let KeyListTestsOnly = "list_only"
private let KeyOSLogPath = "os_log_path"
private let KeyRunnerAppPath = "test_host_path"
private let KeyRunnerTargetPath = "test_target_path"
private let KeyTestArtifactsFilenameGlobs = "test_artifacts_filename_globs"
private let KeyTestBundlePath = "test_bundle_path"
private let KeyTestFilter = "test_filter"
private let KeyTestMirror = "test_mirror"
private let KeyTestTimeout = "test_timeout"
private let KeyTestType = "test_type"
private let KeyVideoRecordingPath = "video_recording_path"
private let KeyWaitForDebugger = "wait_for_debugger"
private let KeyWorkingDirectory = "working_directory"

// MARK: - FBXCTestConfiguration

@objc public class FBXCTestConfiguration: NSObject, NSCopying {

  @objc public let processUnderTestEnvironment: [String: String]
  @objc public let workingDirectory: String
  @objc public let testBundlePath: String
  @objc public let waitForDebugger: Bool
  @objc public let testTimeout: TimeInterval

  @objc public var testType: FBXCTestType {
    fatalError("-[\(type(of: self)) testType] is abstract and should be overridden")
  }

  @objc public init(environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval) {
    self.processUnderTestEnvironment = environment
    self.workingDirectory = workingDirectory
    self.testBundlePath = testBundlePath
    self.waitForDebugger = waitForDebugger

    if let timeoutFromEnv = ProcessInfo.processInfo.environment["FB_TEST_TIMEOUT"],
      let envTimeout = TimeInterval(timeoutFromEnv)
    {
      self.testTimeout = envTimeout
    } else {
      self.testTimeout = timeout > 0 ? timeout : FBXCTestConfiguration.defaultTimeoutValue()
    }
    super.init()
  }

  private static func defaultTimeoutValue() -> TimeInterval {
    return 500
  }

  // MARK: NSObject

  public override var description: String {
    guard let data = try? JSONSerialization.data(withJSONObject: jsonSerializableRepresentation(), options: []) else {
      return super.description
    }
    return String(data: data, encoding: .utf8) ?? super.description
  }

  public override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBXCTestConfiguration else { return false }
    guard type(of: other) == type(of: self) else { return false }
    return processUnderTestEnvironment == other.processUnderTestEnvironment
      && workingDirectory == other.workingDirectory
      && testBundlePath == other.testBundlePath
      && testType.rawValue == other.testType.rawValue
      && waitForDebugger == other.waitForDebugger
      && testTimeout == other.testTimeout
  }

  public override var hash: Int {
    return (processUnderTestEnvironment as NSDictionary).hash ^ (workingDirectory as NSString).hash ^ (testBundlePath as NSString).hash ^ (testType.rawValue as NSString).hash ^ (waitForDebugger ? 1 : 0) ^ Int(testTimeout)
  }

  // MARK: Public

  @objc public func buildEnvironment(withEntries entries: [String: String]) -> [String: String] {
    var parentEnvironment = ProcessInfo.processInfo.environment
    parentEnvironment.removeValue(forKey: "XCTestConfigurationFilePath")

    var environmentOverrides: [String: String] = [:]
    let xctoolTestEnvPrefix = "XCTOOL_TEST_ENV_"
    for (key, value) in parentEnvironment {
      if key.hasPrefix(xctoolTestEnvPrefix) {
        let childKey = String(key.dropFirst(xctoolTestEnvPrefix.count))
        environmentOverrides[childKey] = value
      }
    }
    for (key, value) in entries {
      environmentOverrides[key] = value
    }
    var environment = parentEnvironment
    for (key, value) in environmentOverrides {
      environment[key] = value
    }
    return environment
  }

  // MARK: JSON

  @objc public func jsonSerializableRepresentation() -> [String: Any] {
    return [
      KeyEnvironment: processUnderTestEnvironment,
      KeyWorkingDirectory: workingDirectory,
      KeyTestBundlePath: testBundlePath,
      KeyTestType: testType.rawValue,
      KeyListTestsOnly: false,
      KeyWaitForDebugger: waitForDebugger,
      KeyTestTimeout: testTimeout,
    ]
  }

  // MARK: NSCopying

  @objc public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }
}

// MARK: - FBListTestConfiguration

@objc public final class FBListTestConfiguration: FBXCTestConfiguration {

  @objc public let architectures: Set<String>
  @objc public let runnerAppPath: String?

  @objc public static func configuration(withEnvironment environment: [String: String], workingDirectory: String, testBundlePath: String, runnerAppPath: String?, waitForDebugger: Bool, timeout: TimeInterval, architectures: Set<String>) -> FBListTestConfiguration {
    return FBListTestConfiguration(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, runnerAppPath: runnerAppPath, waitForDebugger: waitForDebugger, timeout: timeout, architectures: architectures)
  }

  @objc public init(environment: [String: String], workingDirectory: String, testBundlePath: String, runnerAppPath: String?, waitForDebugger: Bool, timeout: TimeInterval, architectures: Set<String>) {
    self.runnerAppPath = runnerAppPath
    self.architectures = architectures
    super.init(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, waitForDebugger: waitForDebugger, timeout: timeout)
  }

  @objc public override var testType: FBXCTestType {
    return FBXCTestType.listTest
  }

  @objc public override func jsonSerializableRepresentation() -> [String: Any] {
    var json = super.jsonSerializableRepresentation()
    json[KeyListTestsOnly] = true
    json[KeyRunnerAppPath] = runnerAppPath ?? NSNull()
    return json
  }
}

// MARK: - FBTestManagerTestConfiguration

@objc public final class FBTestManagerTestConfiguration: FBXCTestConfiguration {

  @objc public let runnerAppPath: String
  @objc public let testTargetAppPath: String?
  @objc public let testFilter: String?
  @objc public let osLogPath: String?
  @objc public let videoRecordingPath: String?
  @objc public let testArtifactsFilenameGlobs: [String]?

  @objc public static func configuration(withEnvironment environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval, runnerAppPath: String, testTargetAppPath: String?, testFilter: String?, videoRecordingPath: String?, testArtifactsFilenameGlobs: [String]?, osLogPath: String?) -> FBTestManagerTestConfiguration {
    return FBTestManagerTestConfiguration(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, waitForDebugger: waitForDebugger, timeout: timeout, runnerAppPath: runnerAppPath, testTargetAppPath: testTargetAppPath, testFilter: testFilter, videoRecordingPath: videoRecordingPath, testArtifactsFilenameGlobs: testArtifactsFilenameGlobs, osLogPath: osLogPath)
  }

  @objc public init(environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval, runnerAppPath: String, testTargetAppPath: String?, testFilter: String?, videoRecordingPath: String?, testArtifactsFilenameGlobs: [String]?, osLogPath: String?) {
    self.runnerAppPath = runnerAppPath
    self.testTargetAppPath = testTargetAppPath
    self.testFilter = testFilter
    self.videoRecordingPath = videoRecordingPath
    self.testArtifactsFilenameGlobs = testArtifactsFilenameGlobs
    self.osLogPath = osLogPath
    super.init(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, waitForDebugger: waitForDebugger, timeout: timeout)
  }

  @objc public override var testType: FBXCTestType {
    return testTargetAppPath != nil ? FBXCTestType.uiTest : FBXCTestType.applicationTest
  }

  @objc public override func jsonSerializableRepresentation() -> [String: Any] {
    var json = super.jsonSerializableRepresentation()
    json[KeyRunnerAppPath] = runnerAppPath
    json[KeyRunnerTargetPath] = testTargetAppPath ?? NSNull()
    json[KeyTestFilter] = testFilter ?? NSNull()
    json[KeyVideoRecordingPath] = videoRecordingPath ?? NSNull()
    json[KeyTestArtifactsFilenameGlobs] = testArtifactsFilenameGlobs ?? NSNull()
    json[KeyOSLogPath] = osLogPath ?? NSNull()
    return json
  }
}

// MARK: - FBLogicTestConfiguration

@objc public final class FBLogicTestConfiguration: FBXCTestConfiguration {

  @objc public let testFilter: String?
  @objc public let mirroring: FBLogicTestMirrorLogs
  @objc public let coverageConfiguration: FBCodeCoverageConfiguration?
  @objc public let binaryPath: String?
  @objc public let logDirectoryPath: String?
  @objc public let architectures: Set<String>

  @objc public static func configuration(withEnvironment environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval, testFilter: String?, mirroring: FBLogicTestMirrorLogs, coverageConfiguration: FBCodeCoverageConfiguration?, binaryPath: String?, logDirectoryPath: String?, architectures: Set<String>) -> FBLogicTestConfiguration {
    return FBLogicTestConfiguration(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, waitForDebugger: waitForDebugger, timeout: timeout, testFilter: testFilter, mirroring: mirroring, coverageConfiguration: coverageConfiguration, binaryPath: binaryPath, logDirectoryPath: logDirectoryPath, architectures: architectures)
  }

  @objc public init(environment: [String: String], workingDirectory: String, testBundlePath: String, waitForDebugger: Bool, timeout: TimeInterval, testFilter: String?, mirroring: FBLogicTestMirrorLogs, coverageConfiguration: FBCodeCoverageConfiguration?, binaryPath: String?, logDirectoryPath: String?, architectures: Set<String>) {
    self.testFilter = testFilter
    self.mirroring = mirroring
    self.coverageConfiguration = coverageConfiguration
    self.binaryPath = binaryPath
    self.logDirectoryPath = logDirectoryPath
    self.architectures = architectures
    super.init(environment: environment, workingDirectory: workingDirectory, testBundlePath: testBundlePath, waitForDebugger: waitForDebugger, timeout: timeout)
  }

  @objc public override var testType: FBXCTestType {
    return FBXCTestType.logicTest
  }

  @objc public override func jsonSerializableRepresentation() -> [String: Any] {
    var json = super.jsonSerializableRepresentation()
    json[KeyTestFilter] = testFilter ?? NSNull()
    return json
  }
}
