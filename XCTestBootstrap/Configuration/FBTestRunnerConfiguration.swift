/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let kEnvShimStartXCTest = "SHIMULATOR_START_XCTEST"
private let kEnvWaitForDebugger = "XCTOOL_WAIT_FOR_DEBUGGER"
private let kEnvLLVMProfileFile = "LLVM_PROFILE_FILE"
private let kEnvLogDirectoryPath = "LOG_DIRECTORY_PATH"

@objc(FBTestRunnerConfiguration)
public class FBTestRunnerConfiguration: NSObject, NSCopying {

  // MARK: Properties

  @objc public let sessionIdentifier: UUID
  @objc public let testRunner: FBBundleDescriptor
  @objc public let launchEnvironment: [String: String]
  @objc public let testedApplicationAdditionalEnvironment: [String: String]
  @objc public let testConfiguration: FBTestConfiguration

  @objc public var launchArguments: [String] {
    return [
      "-NSTreatUnknownArgumentsAsOpen", "NO",
      "-ApplePersistenceIgnoreState", "YES",
    ]
  }

  // MARK: Initializers

  @objc
  public init(sessionIdentifier: UUID, testRunner: FBBundleDescriptor, launchEnvironment: [String: String], testedApplicationAdditionalEnvironment: [String: String], testConfiguration: FBTestConfiguration) {
    self.sessionIdentifier = sessionIdentifier
    self.testRunner = testRunner
    self.launchEnvironment = launchEnvironment
    self.testedApplicationAdditionalEnvironment = testedApplicationAdditionalEnvironment
    self.testConfiguration = testConfiguration
    super.init()
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  // MARK: Public

  public class func prepareConfiguration(withTarget target: FBiOSTarget & AsyncApplicationCommands & AsyncXCTestExtendedCommands, testLaunchConfiguration: FBTestLaunchConfiguration, workingDirectory: String, codesign: FBCodesignProvider?) -> FBFuture<FBTestRunnerConfiguration> {
    if let codesign {
      return unsafeBitCast(
        codesign.cdHashForBundle(atPath: testLaunchConfiguration.testBundle.path)
          .rephraseFailure("Could not determine bundle at path '\(testLaunchConfiguration.testBundle.path)' is codesigned and codesigning is required")
          .onQueue(
            target.asyncQueue,
            fmap: { (_: AnyObject) -> FBFuture<AnyObject> in
              return unsafeBitCast(
                self.prepareConfigurationAfterCodesignatureCheck(withTarget: target, testLaunchConfiguration: testLaunchConfiguration, workingDirectory: workingDirectory),
                to: FBFuture<AnyObject>.self
              )
            }),
        to: FBFuture<FBTestRunnerConfiguration>.self
      )
    }
    return prepareConfigurationAfterCodesignatureCheck(withTarget: target, testLaunchConfiguration: testLaunchConfiguration, workingDirectory: workingDirectory)
  }

  @objc(launchEnvironmentWithHostApplication:hostApplicationAdditionalEnvironment:testBundle:testConfigurationPath:frameworkSearchPaths:)
  public class func launchEnvironment(withHostApplication hostApplication: FBBundleDescriptor, hostApplicationAdditionalEnvironment: [String: String], testBundle: FBBundleDescriptor, testConfigurationPath: String, frameworkSearchPaths: [String]) -> [String: String] {
    var environmentVariables = hostApplicationAdditionalEnvironment
    let frameworkSearchPath = frameworkSearchPaths.joined(separator: ":")
    environmentVariables["AppTargetLocation"] = hostApplication.binary?.path ?? ""
    environmentVariables["DYLD_FALLBACK_FRAMEWORK_PATH"] = frameworkSearchPath.isEmpty ? "" : frameworkSearchPath
    environmentVariables["DYLD_FALLBACK_LIBRARY_PATH"] = frameworkSearchPath.isEmpty ? "" : frameworkSearchPath
    environmentVariables["OBJC_DISABLE_GC"] = "YES"
    environmentVariables["TestBundleLocation"] = testBundle.path
    environmentVariables["XCODE_DBG_XPC_EXCLUSIONS"] = "com.apple.dt.xctestSymbolicator"
    environmentVariables["XCTestConfigurationFilePath"] = testConfigurationPath
    return addAdditionalEnvironmentVariables(environmentVariables)
  }

  // MARK: Private

  private class func addAdditionalEnvironmentVariables(_ currentEnvironmentVariables: [String: String]) -> [String: String] {
    let prefix = "CUSTOM_"
    var envs = currentEnvironmentVariables
    for (key, value) in ProcessInfo.processInfo.environment {
      if key.hasPrefix(prefix) {
        envs[String(key.dropFirst(prefix.count))] = value
      }
    }
    return envs
  }

  private class func prepareConfigurationAfterCodesignatureCheck(withTarget target: FBiOSTarget & AsyncApplicationCommands & AsyncXCTestExtendedCommands, testLaunchConfiguration: FBTestLaunchConfiguration, workingDirectory: String) -> FBFuture<FBTestRunnerConfiguration> {
    // Common Paths
    let runtimeRoot = target.runtimeRootDirectory
    let platformRoot = target.platformRootDirectory

    // This directory will contain XCTest.framework, built for the target platform.
    let platformDeveloperFrameworksPath = (platformRoot as NSString).appendingPathComponent("Developer/Library/Frameworks")
    // Container directory for XCTest related Frameworks.
    let developerLibraryPath = (runtimeRoot as NSString).appendingPathComponent("Developer/Library")
    // Contains other frameworks, depended on by XCTest and Instruments
    let xcTestFrameworksPaths = [
      (developerLibraryPath as NSString).appendingPathComponent("Frameworks"),
      (developerLibraryPath as NSString).appendingPathComponent("PrivateFrameworks"),
      platformDeveloperFrameworksPath,
    ]

    let automationFrameworkPath = (developerLibraryPath as NSString).appendingPathComponent("PrivateFrameworks/XCTAutomationSupport.framework")
    let automationFrameworkPathOrNil: String? = FileManager.default.fileExists(atPath: automationFrameworkPath) ? automationFrameworkPath : nil

    var testedApplicationAdditionalEnvironment: [String: String] = [:]
    let xctTargetBootstrapInjectPath = (platformRoot as NSString).appendingPathComponent("Developer/usr/lib/libXCTTargetBootstrapInject.dylib")
    // Xcode > 12.5 does not have this file neither requires its injection in the target test app.
    if FileManager.default.fileExists(atPath: xctTargetBootstrapInjectPath) {
      testedApplicationAdditionalEnvironment["DYLD_INSERT_LIBRARIES"] = xctTargetBootstrapInjectPath
    }

    var testApplicationDependencies: [String: String]?
    if let identifier = testLaunchConfiguration.targetApplicationBundle?.identifier,
      let path = testLaunchConfiguration.targetApplicationBundle?.path
    {
      testApplicationDependencies = [identifier: path]
    }

    // Prepare XCTest bundle
    let sessionIdentifier = UUID()
    let testBundle: FBBundleDescriptor
    do {
      testBundle = try FBBundleDescriptor.bundle(fromPath: testLaunchConfiguration.testBundle.path)
    } catch {
      return unsafeBitCast(
        XCTestBootstrapError
          .describe("Failed to prepare test bundle")
          .caused(by: error)
          .failFuture(),
        to: FBFuture<FBTestRunnerConfiguration>.self
      )
    }

    // Prepare the test configuration
    let testConfiguration: FBTestConfiguration
    do {
      testConfiguration = try FBTestConfiguration(
        byWritingToFileWithSessionIdentifier: sessionIdentifier,
        moduleName: testBundle.name,
        testBundlePath: testBundle.path,
        uiTesting: testLaunchConfiguration.shouldInitializeUITesting,
        testsToRun: testLaunchConfiguration.testsToRun,
        testsToSkip: testLaunchConfiguration.testsToSkip,
        targetApplicationPath: testLaunchConfiguration.targetApplicationBundle?.path,
        targetApplicationBundleID: testLaunchConfiguration.targetApplicationBundle?.identifier,
        testApplicationDependencies: testApplicationDependencies,
        automationFrameworkPath: automationFrameworkPathOrNil,
        reportActivities: testLaunchConfiguration.reportActivities
      )
    } catch {
      return unsafeBitCast(
        XCTestBootstrapError
          .describe("Failed to prepare test configuration")
          .caused(by: error)
          .failFuture(),
        to: FBFuture<FBTestRunnerConfiguration>.self
      )
    }

    let installedAppFuture: FBFuture<FBInstalledApplication> = fbFutureFromAsync {
      try await target.installedApplication(bundleID: testLaunchConfiguration.applicationLaunchConfiguration.bundleID)
    }
    let shimFuture: FBFuture<AnyObject> = fbFutureFromAsync {
      try await target.extendedTestShim() as AnyObject
    }
    return unsafeBitCast(
      FBFuture<AnyObject>.combine([
        unsafeBitCast(installedAppFuture, to: FBFuture<AnyObject>.self),
        shimFuture,
      ])
      .onQueue(
        target.asyncQueue,
        map: { (tupleObj: AnyObject) -> AnyObject in
          let tuple = tupleObj as! NSArray
          let hostApplication = tuple[0] as! FBInstalledApplication
          let shimPath = tuple[1] as! String

          var hostApplicationAdditionalEnvironment: [String: String] = [:]
          hostApplicationAdditionalEnvironment[kEnvShimStartXCTest] = "1"
          hostApplicationAdditionalEnvironment["DYLD_INSERT_LIBRARIES"] = shimPath
          hostApplicationAdditionalEnvironment[kEnvWaitForDebugger] = testLaunchConfiguration.applicationLaunchConfiguration.waitForDebugger ? "YES" : "NO"

          if let coverageDirectoryPath = testLaunchConfiguration.coverageDirectoryPath {
            let continuousCoverageCollectionMode = testLaunchConfiguration.shouldEnableContinuousCoverageCollection ? "%c" : ""
            let hostCoverageFile = "coverage_\(hostApplication.bundle.identifier)\(continuousCoverageCollectionMode).profraw"
            let hostCoveragePath = (coverageDirectoryPath as NSString).appendingPathComponent(hostCoverageFile)
            hostApplicationAdditionalEnvironment[kEnvLLVMProfileFile] = hostCoveragePath

            if let targetBundle = testLaunchConfiguration.targetApplicationBundle {
              let targetCoverageFile = "coverage_\(targetBundle.identifier)\(continuousCoverageCollectionMode).profraw"
              let targetAppCoveragePath = (coverageDirectoryPath as NSString).appendingPathComponent(targetCoverageFile)
              testedApplicationAdditionalEnvironment[kEnvLLVMProfileFile] = targetAppCoveragePath
            }
          }

          if let logDirectoryPath = testLaunchConfiguration.logDirectoryPath {
            hostApplicationAdditionalEnvironment[kEnvLogDirectoryPath] = logDirectoryPath
          }

          let frameworkSearchPaths = xcTestFrameworksPaths + [(hostApplication.bundle.path as NSString).appendingPathComponent("Frameworks")]

          let launchEnvironment = FBTestRunnerConfiguration.launchEnvironment(
            withHostApplication: hostApplication.bundle,
            hostApplicationAdditionalEnvironment: hostApplicationAdditionalEnvironment,
            testBundle: testBundle,
            testConfigurationPath: testConfiguration.path,
            frameworkSearchPaths: frameworkSearchPaths
          )

          return FBTestRunnerConfiguration(
            sessionIdentifier: sessionIdentifier,
            testRunner: hostApplication.bundle,
            launchEnvironment: launchEnvironment,
            testedApplicationAdditionalEnvironment: testedApplicationAdditionalEnvironment,
            testConfiguration: testConfiguration
          )
        }),
      to: FBFuture<FBTestRunnerConfiguration>.self
    )
  }
}
