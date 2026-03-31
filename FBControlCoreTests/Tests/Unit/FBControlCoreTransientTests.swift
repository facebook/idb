/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import FBControlCore

final class FBControlCoreTransientTests: XCTestCase {

  private func makeIO() -> FBProcessIO<AnyObject, AnyObject, AnyObject> {
    return FBProcessIO<AnyObject, AnyObject, AnyObject>(stdIn: nil, stdOut: nil, stdErr: nil)
  }

  private func makeBundle(name: String = "App", identifier: String = "com.test", path: String = "/tmp") -> FBBundleDescriptor {
    return FBBundleDescriptor(name: name, identifier: identifier, path: path, binary: nil)
  }

  private func makeAppLaunch(
    bundleID: String = "com.test.host",
    bundleName: String? = nil,
    launchMode: FBApplicationLaunchMode = .failIfRunning
  ) -> FBApplicationLaunchConfiguration {
    return FBApplicationLaunchConfiguration(
      bundleID: bundleID,
      bundleName: bundleName,
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      io: makeIO(),
      launchMode: launchMode
    )
  }

  // MARK: FBBundleDescriptor

  func testBundleDescriptorInitAndProperties() {
    let bundle = FBBundleDescriptor(name: "MyApp", identifier: "com.example.app", path: "/tmp/MyApp.app", binary: nil)

    XCTAssertEqual(bundle.name, "MyApp")
    XCTAssertEqual(bundle.identifier, "com.example.app")
    XCTAssertEqual(bundle.path, "/tmp/MyApp.app")
    XCTAssertNil(bundle.binary)
  }

  func testBundleDescriptorEqualityWithNilBinary() {
    let a = FBBundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: nil)
    let b = FBBundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: nil)

    // ObjC isEqual sends [nil isEqual:nil] which returns NO
    XCTAssertNotEqual(a, b)
  }

  func testBundleDescriptorWithBinaryEquality() throws {
    let binary = try FBBinaryDescriptor.binary(withPath: "/usr/bin/codesign")
    let a = FBBundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: binary)
    let b = FBBundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: binary)

    XCTAssertEqual(a, b)
  }

  func testBundleDescriptorInequalityByIdentifier() throws {
    let binary = try FBBinaryDescriptor.binary(withPath: "/usr/bin/codesign")
    let a = FBBundleDescriptor(name: "App", identifier: "com.test.a", path: "/a", binary: binary)
    let b = FBBundleDescriptor(name: "App", identifier: "com.test.b", path: "/a", binary: binary)

    XCTAssertNotEqual(a, b)
  }

  func testBundleDescriptorCopyReturnsSelf() {
    let bundle = makeBundle()
    let copy = bundle.copy() as AnyObject

    XCTAssertTrue(bundle === copy)
  }

  func testBundleDescriptorDescription() {
    let bundle = FBBundleDescriptor(name: "TestApp", identifier: "com.example.test", path: "/tmp/test", binary: nil)

    XCTAssertTrue(bundle.description.contains("TestApp"))
    XCTAssertTrue(bundle.description.contains("com.example.test"))
  }

  func testBundleFromInvalidPathThrows() {
    XCTAssertThrowsError(try FBBundleDescriptor.bundle(fromPath: "/nonexistent/path"))
  }

  func testIsApplicationAtPathForNonAppPath() {
    XCTAssertFalse(FBBundleDescriptor.isApplication(atPath: "/tmp/notanapp"))
    XCTAssertFalse(FBBundleDescriptor.isApplication(atPath: "/tmp/file.txt"))
  }

  // MARK: FBInstalledApplication

  func testInstalledApplicationInitWithEnum() {
    let bundle = makeBundle()
    let app = FBInstalledApplication(bundle: bundle, installType: .user, dataContainer: "/data")

    XCTAssertTrue(app.bundle === bundle)
    XCTAssertEqual(app.installType, .user)
    XCTAssertEqual(app.dataContainer, "/data")
  }

  func testInstalledApplicationInstallTypeStringConversion() {
    let bundle = makeBundle()

    XCTAssertEqual(FBInstalledApplication(bundle: bundle, installType: .user, dataContainer: nil as String?).installTypeString, "user")
    XCTAssertEqual(FBInstalledApplication(bundle: bundle, installType: .system, dataContainer: nil as String?).installTypeString, "system")
    XCTAssertEqual(FBInstalledApplication(bundle: bundle, installType: .mac, dataContainer: nil as String?).installTypeString, "mac")
    XCTAssertEqual(FBInstalledApplication(bundle: bundle, installType: .unknown, dataContainer: nil as String?).installTypeString, "unknown")
    XCTAssertEqual(FBInstalledApplication(bundle: bundle, installType: .userDevelopment, dataContainer: nil as String?).installTypeString, "user_development")
    XCTAssertEqual(FBInstalledApplication(bundle: bundle, installType: .userEnterprise, dataContainer: nil as String?).installTypeString, "user_enterprise")
  }

  func testInstalledApplicationFromInstallTypeString() {
    let bundle = makeBundle()

    XCTAssertEqual(FBInstalledApplication(bundle: bundle, installTypeString: "System", signerIdentity: nil, dataContainer: nil as String?).installType, .system)
    XCTAssertEqual(FBInstalledApplication(bundle: bundle, installTypeString: "User", signerIdentity: nil, dataContainer: nil as String?).installType, .user)
    XCTAssertEqual(FBInstalledApplication(bundle: bundle, installTypeString: "mac", signerIdentity: nil, dataContainer: nil as String?).installType, .mac)
    XCTAssertEqual(FBInstalledApplication(bundle: bundle, installTypeString: nil, signerIdentity: nil, dataContainer: nil as String?).installType, .unknown)
  }

  func testInstalledApplicationSignerIdentityEnterprise() {
    let bundle = makeBundle()
    let app = FBInstalledApplication(bundle: bundle, installTypeString: "User", signerIdentity: "iPhone Distribution: Example Corp", dataContainer: nil as String?)
    XCTAssertEqual(app.installType, .userEnterprise)
  }

  func testInstalledApplicationSignerIdentityDevelopment() {
    let bundle = makeBundle()

    let devApp = FBInstalledApplication(bundle: bundle, installTypeString: "User", signerIdentity: "iPhone Developer: test@example.com", dataContainer: nil as String?)
    XCTAssertEqual(devApp.installType, .userDevelopment)

    let appleDevApp = FBInstalledApplication(bundle: bundle, installTypeString: "User", signerIdentity: "Apple Development: test@example.com", dataContainer: nil as String?)
    XCTAssertEqual(appleDevApp.installType, .userDevelopment)
  }

  func testInstalledApplicationEquality() throws {
    let binary = try FBBinaryDescriptor.binary(withPath: "/usr/bin/codesign")
    let bundle = FBBundleDescriptor(name: "App", identifier: "com.test", path: "/tmp", binary: binary)
    let a = FBInstalledApplication(bundle: bundle, installType: .user, dataContainer: "/data")
    let b = FBInstalledApplication(bundle: bundle, installType: .user, dataContainer: "/data")
    let c = FBInstalledApplication(bundle: bundle, installType: .system, dataContainer: "/data")

    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
  }

  func testInstalledApplicationCopyReturnsSelf() {
    let app = FBInstalledApplication(bundle: makeBundle(), installType: .user, dataContainer: nil as String?)
    let copy = app.copy() as AnyObject

    XCTAssertTrue(app === copy)
  }

  func testInstalledApplicationDescription() {
    let app = FBInstalledApplication(bundle: makeBundle(), installType: .user, dataContainer: "/data/container")

    XCTAssertTrue(app.description.contains("user"))
    XCTAssertTrue(app.description.contains("/data/container"))
  }

  func testInstalledApplicationNilDataContainer() {
    let app = FBInstalledApplication(bundle: makeBundle(), installType: .user, dataContainer: nil as String?)
    XCTAssertNil(app.dataContainer)
  }

  // MARK: FBProcessInfo

  func testProcessInfoInitAndProperties() {
    let info = FBProcessInfo(processIdentifier: 42, launchPath: "/usr/bin/ls", arguments: ["-la"], environment: ["HOME": "/Users/test"])

    XCTAssertEqual(info.processIdentifier, 42)
    XCTAssertEqual(info.launchPath, "/usr/bin/ls")
    XCTAssertEqual(info.arguments, ["-la"])
    XCTAssertEqual(info.environment, ["HOME": "/Users/test"])
  }

  func testProcessInfoProcessName() {
    let info = FBProcessInfo(processIdentifier: 1, launchPath: "/usr/bin/some_tool", arguments: [], environment: [:])
    XCTAssertEqual(info.processName, "some_tool")
  }

  func testProcessInfoEquality() {
    let a = FBProcessInfo(processIdentifier: 10, launchPath: "/usr/bin/ls", arguments: ["-la"], environment: ["A": "B"])
    let b = FBProcessInfo(processIdentifier: 10, launchPath: "/usr/bin/ls", arguments: ["-la"], environment: ["A": "B"])
    let c = FBProcessInfo(processIdentifier: 11, launchPath: "/usr/bin/ls", arguments: ["-la"], environment: ["A": "B"])

    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
  }

  func testProcessInfoEqualityIgnoresEnvironment() {
    let a = FBProcessInfo(processIdentifier: 10, launchPath: "/usr/bin/ls", arguments: [], environment: ["X": "1"])
    let b = FBProcessInfo(processIdentifier: 10, launchPath: "/usr/bin/ls", arguments: [], environment: ["Y": "2"])

    XCTAssertEqual(a, b)
  }

  func testProcessInfoCopyReturnsSelf() {
    let info = FBProcessInfo(processIdentifier: 1, launchPath: "/bin/sh", arguments: [], environment: [:])
    let copy = info.copy() as AnyObject
    XCTAssertTrue(info === copy)
  }

  func testProcessInfoDescription() {
    let info = FBProcessInfo(processIdentifier: 99, launchPath: "/usr/bin/ruby", arguments: [], environment: [:])
    XCTAssertTrue(info.description.contains("ruby"))
    XCTAssertTrue(info.description.contains("99"))
  }

  func testProcessInfoHash() {
    let a = FBProcessInfo(processIdentifier: 10, launchPath: "/usr/bin/ls", arguments: ["-la"], environment: [:])
    let b = FBProcessInfo(processIdentifier: 10, launchPath: "/usr/bin/ls", arguments: ["-la"], environment: [:])
    XCTAssertEqual(a.hash, b.hash)
  }

  // MARK: FBApplicationLaunchConfiguration

  func testApplicationLaunchConfigurationInit() {
    let config = FBApplicationLaunchConfiguration(
      bundleID: "com.example.app",
      bundleName: "ExampleApp",
      arguments: ["--verbose"],
      environment: ["DEBUG": "1"],
      waitForDebugger: true,
      io: makeIO(),
      launchMode: .relaunchIfRunning
    )

    XCTAssertEqual(config.bundleID, "com.example.app")
    XCTAssertEqual(config.bundleName, "ExampleApp")
    XCTAssertEqual(config.arguments, ["--verbose"])
    XCTAssertEqual(config.environment, ["DEBUG": "1"])
    XCTAssertTrue(config.waitForDebugger)
    XCTAssertEqual(config.launchMode, .relaunchIfRunning)
  }

  func testApplicationLaunchConfigurationNilBundleName() {
    let config = makeAppLaunch()
    XCTAssertNil(config.bundleName)
    XCTAssertEqual(config.launchMode, .failIfRunning)
  }

  func testApplicationLaunchConfigurationEquality() {
    let io = makeIO()
    let a = FBApplicationLaunchConfiguration(bundleID: "com.app", bundleName: "App", arguments: [], environment: [:], waitForDebugger: false, io: io, launchMode: .failIfRunning)
    let b = FBApplicationLaunchConfiguration(bundleID: "com.app", bundleName: "App", arguments: [], environment: [:], waitForDebugger: false, io: io, launchMode: .failIfRunning)

    XCTAssertEqual(a, b)
  }

  func testApplicationLaunchConfigurationInequalityByMode() {
    let a = makeAppLaunch(launchMode: .failIfRunning)
    let b = makeAppLaunch(launchMode: .relaunchIfRunning)

    XCTAssertNotEqual(a, b)
  }

  func testApplicationLaunchConfigurationDescription() {
    let config = FBApplicationLaunchConfiguration(
      bundleID: "com.example.app",
      bundleName: "MyApp",
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      io: makeIO(),
      launchMode: .failIfRunning
    )

    XCTAssertTrue(config.description.contains("com.example.app"))
    XCTAssertTrue(config.description.contains("MyApp"))
  }

  // MARK: FBProcessSpawnConfiguration

  func testProcessSpawnConfigurationInit() {
    let config = FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>(
      launchPath: "/usr/bin/env",
      arguments: ["echo", "hello"],
      environment: ["PATH": "/usr/bin"],
      io: makeIO(),
      mode: .posixSpawn
    )

    XCTAssertEqual(config.launchPath, "/usr/bin/env")
    XCTAssertEqual(config.arguments, ["echo", "hello"])
    XCTAssertEqual(config.environment, ["PATH": "/usr/bin"])
    XCTAssertEqual(config.mode, .posixSpawn)
  }

  func testProcessSpawnConfigurationProcessName() {
    let config = FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>(
      launchPath: "/usr/local/bin/my_tool",
      arguments: [],
      environment: [:],
      io: makeIO(),
      mode: .default
    )

    XCTAssertEqual(config.processName, "my_tool")
  }

  func testProcessSpawnConfigurationEquality() {
    let io = makeIO()
    let a = FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>(launchPath: "/usr/bin/env", arguments: ["a"], environment: ["K": "V"], io: io, mode: .posixSpawn)
    let b = FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>(launchPath: "/usr/bin/env", arguments: ["a"], environment: ["K": "V"], io: io, mode: .posixSpawn)

    XCTAssertEqual(a, b)
  }

  func testProcessSpawnConfigurationInequalityByMode() {
    let io = makeIO()
    let a = FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>(launchPath: "/usr/bin/env", arguments: [], environment: [:], io: io, mode: .posixSpawn)
    let b = FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>(launchPath: "/usr/bin/env", arguments: [], environment: [:], io: io, mode: .launchd)

    XCTAssertNotEqual(a, b)
  }

  func testProcessSpawnConfigurationDescription() {
    let config = FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>(
      launchPath: "/usr/bin/env",
      arguments: ["--help"],
      environment: [:],
      io: makeIO(),
      mode: .default
    )

    XCTAssertTrue(config.description.contains("/usr/bin/env"))
  }

  // MARK: FBCollectionInformation

  func testOneLineDescriptionFromArray() {
    let result = FBCollectionInformation.oneLineDescription(from: ["alpha", "beta", "gamma"])
    XCTAssertEqual(result, "[alpha, beta, gamma]")
  }

  func testOneLineDescriptionFromEmptyArray() {
    let result = FBCollectionInformation.oneLineDescription(from: [])
    XCTAssertEqual(result, "[]")
  }

  func testOneLineDescriptionFromDictionary() {
    let result = FBCollectionInformation.oneLineDescription(from: ["key": "value"])
    XCTAssertTrue(result.contains("key => value"))
    XCTAssertTrue(result.hasPrefix("{"))
    XCTAssertTrue(result.hasSuffix("}"))
  }

  func testOneLineDescriptionFromEmptyDictionary() {
    let result = FBCollectionInformation.oneLineDescription(from: [:])
    XCTAssertEqual(result, "{}")
  }

  func testIsArrayHeterogeneousWithMatchingClass() {
    XCTAssertTrue(FBCollectionInformation.isArrayHeterogeneous(["a", "b", "c"], with: NSString.self))
  }

  func testIsArrayHeterogeneousWithMismatchedClass() {
    let mixed: [Any] = ["a", NSNumber(value: 1), "b"]
    XCTAssertFalse(FBCollectionInformation.isArrayHeterogeneous(mixed as [AnyObject], with: NSString.self))
  }

  func testIsArrayHeterogeneousWithEmptyArray() {
    XCTAssertTrue(FBCollectionInformation.isArrayHeterogeneous([], with: NSString.self))
  }

  func testIsDictionaryHeterogeneousWithMatchingClasses() {
    let dict: NSDictionary = ["a": "b", "c": "d"]
    XCTAssertTrue(FBCollectionInformation.isDictionaryHeterogeneous(dict as! [AnyHashable: Any], keyClass: NSString.self, valueClass: NSString.self))
  }

  func testIsDictionaryHeterogeneousWithMismatchedValues() {
    let dict: NSDictionary = ["a": "b", "c": NSNumber(value: 1)]
    XCTAssertFalse(FBCollectionInformation.isDictionaryHeterogeneous(dict as! [AnyHashable: Any], keyClass: NSString.self, valueClass: NSString.self))
  }

  // MARK: FBCollectionOperations

  func testArrayFromIndices() {
    var indexSet = IndexSet()
    indexSet.insert(1)
    indexSet.insert(3)
    indexSet.insert(5)
    let result = FBCollectionOperations.array(from: indexSet)
    XCTAssertEqual(result, [1, 3, 5] as [NSNumber])
  }

  func testIndicesFromArray() {
    let result = FBCollectionOperations.indices(from: [2, 4, 6]) as IndexSet
    var expected = IndexSet()
    expected.insert(2)
    expected.insert(4)
    expected.insert(6)
    XCTAssertEqual(result, expected)
  }

  func testArrayFromIndicesRoundTrip() {
    let original: [NSNumber] = [0, 10, 20]
    let indexSet = FBCollectionOperations.indices(from: original)
    let roundTripped = FBCollectionOperations.array(from: indexSet)
    XCTAssertEqual(roundTripped, original)
  }

  func testRecursiveFilteredJSONDictionary() {
    let input: [String: Any] = [
      "string": "hello",
      "number": 42,
      "nested": ["inner": "value"],
      "nonSerializable": NSDate(),
      "array": [1, "two", NSDate()] as [Any],
    ]
    let result = FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: input)

    XCTAssertEqual(result["string"] as? String, "hello")
    XCTAssertEqual(result["number"] as? Int, 42)
    XCTAssertNotNil(result["nested"])
    XCTAssertNil(result["nonSerializable"])

    let filteredArray = result["array"] as? [Any]
    XCTAssertNotNil(filteredArray)
    XCTAssertEqual(filteredArray?.count, 2)
  }

  func testRecursiveFilteredJSONArray() {
    let input: [Any] = ["hello", 42, NSDate(), ["key": "value"]]
    let result = FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: input)

    XCTAssertEqual(result.count, 3)
    XCTAssertEqual(result[0] as? String, "hello")
    XCTAssertEqual(result[1] as? Int, 42)
    XCTAssertNotNil(result[2] as? [String: String])
  }

  func testNullableValueForDictionaryReturnsValue() {
    let dict: NSDictionary = ["key": "value"]
    let result = FBCollectionOperations.nullableValue(for: dict as! [AnyHashable: Any], key: "key" as NSString)
    XCTAssertEqual(result as? String, "value")
  }

  func testNullableValueForDictionaryReturnsNilForNSNull() {
    let dict: NSDictionary = ["key": NSNull()]
    let result = FBCollectionOperations.nullableValue(for: dict as! [AnyHashable: Any], key: "key" as NSString)
    XCTAssertNil(result)
  }

  func testNullableValueForDictionaryReturnsNilForMissingKey() {
    let dict: NSDictionary = ["key": "value"]
    let result = FBCollectionOperations.nullableValue(for: dict as! [AnyHashable: Any], key: "missing" as NSString)
    XCTAssertNil(result)
  }

  func testArrayWithObjectCount() {
    let result = FBCollectionOperations.array(with: "x", count: 3)
    XCTAssertEqual(result.count, 3)
    for item in result {
      XCTAssertEqual(item as? String, "x")
    }
  }

  func testArrayWithObjectCountZero() {
    let result = FBCollectionOperations.array(with: "x", count: 0)
    XCTAssertEqual(result.count, 0)
  }

  // MARK: FBEventReporterSubject

  func testSubjectForEvent() {
    let subject = FBEventReporterSubject(forEvent: "my_event")

    XCTAssertEqual(subject.eventName, "my_event")
    XCTAssertEqual(subject.eventType, FBEventType.discrete)
    XCTAssertNil(subject.arguments)
    XCTAssertNil(subject.duration)
    XCTAssertNil(subject.size)
    XCTAssertNil(subject.message)
  }

  func testSubjectForStartedCall() {
    let subject = FBEventReporterSubject(forStartedCall: "install", arguments: ["com.app"])

    XCTAssertEqual(subject.eventName, "install")
    XCTAssertEqual(subject.eventType, FBEventType.started)
    XCTAssertEqual(subject.arguments, ["com.app"])
    XCTAssertNil(subject.duration)
  }

  func testSubjectForSuccessfulCall() {
    let subject = FBEventReporterSubject(forSuccessfulCall: "install", duration: 1.5, size: 1024, arguments: ["arg1"])

    XCTAssertEqual(subject.eventName, "install")
    XCTAssertEqual(subject.eventType, FBEventType.success)
    XCTAssertEqual(subject.arguments, ["arg1"])
    XCTAssertEqual(subject.duration, 1500)
    XCTAssertEqual(subject.size, 1024)
    XCTAssertNil(subject.message)
  }

  func testSubjectForFailingCall() {
    let subject = FBEventReporterSubject(forFailingCall: "install", duration: 0.25, message: "timeout", size: nil as NSNumber?, arguments: [])

    XCTAssertEqual(subject.eventName, "install")
    XCTAssertEqual(subject.eventType, FBEventType.failure)
    XCTAssertEqual(subject.message, "timeout")
    XCTAssertEqual(subject.duration, 250)
    XCTAssertNil(subject.size)
  }

  func testEventTypeConstants() {
    XCTAssertEqual(FBEventType.started.rawValue, "started")
    XCTAssertEqual(FBEventType.ended.rawValue, "ended")
    XCTAssertEqual(FBEventType.discrete.rawValue, "discrete")
    XCTAssertEqual(FBEventType.success.rawValue, "success")
    XCTAssertEqual(FBEventType.failure.rawValue, "failure")
  }

  // MARK: FBTestLaunchConfiguration

  func testTestLaunchConfigurationInit() {
    let testBundle = makeBundle(name: "Tests", identifier: "com.test.unit", path: "/tmp/Tests.xctest")
    let appLaunch = makeAppLaunch(bundleName: "Host")
    let testsToRun: Set<String> = ["TestClass/testMethod"]
    let testsToSkip: Set<String> = ["TestClass/testSkipped"]

    let config = FBTestLaunchConfiguration(
      testBundle: testBundle,
      applicationLaunchConfiguration: appLaunch,
      testHostBundle: nil,
      timeout: 300,
      initializeUITesting: true,
      useXcodebuild: false,
      testsToRun: testsToRun,
      testsToSkip: testsToSkip,
      targetApplicationBundle: nil,
      xcTestRunProperties: nil,
      resultBundlePath: "/tmp/results",
      reportActivities: true,
      coverageDirectoryPath: "/tmp/coverage",
      enableContinuousCoverageCollection: false,
      logDirectoryPath: "/tmp/logs",
      reportResultBundle: true
    )

    XCTAssertTrue(config.testBundle === testBundle)
    XCTAssertEqual(config.applicationLaunchConfiguration, appLaunch)
    XCTAssertNil(config.testHostBundle)
    XCTAssertEqual(config.timeout, 300)
    XCTAssertTrue(config.shouldInitializeUITesting)
    XCTAssertFalse(config.shouldUseXcodebuild)
    XCTAssertEqual(config.testsToRun, testsToRun)
    XCTAssertEqual(config.testsToSkip, testsToSkip)
    XCTAssertNil(config.targetApplicationBundle)
    XCTAssertNil(config.xcTestRunProperties)
    XCTAssertEqual(config.resultBundlePath, "/tmp/results")
    XCTAssertTrue(config.reportActivities)
    XCTAssertEqual(config.coverageDirectoryPath, "/tmp/coverage")
    XCTAssertFalse(config.shouldEnableContinuousCoverageCollection)
    XCTAssertEqual(config.logDirectoryPath, "/tmp/logs")
    XCTAssertTrue(config.reportResultBundle)
  }

  func testTestLaunchConfigurationCopy() {
    let testBundle = makeBundle(name: "Tests", identifier: "com.test.unit", path: "/tmp/Tests.xctest")
    let appLaunch = makeAppLaunch()

    let config = FBTestLaunchConfiguration(
      testBundle: testBundle,
      applicationLaunchConfiguration: appLaunch,
      testHostBundle: nil,
      timeout: 60,
      initializeUITesting: false,
      useXcodebuild: false,
      testsToRun: nil,
      testsToSkip: nil,
      targetApplicationBundle: nil,
      xcTestRunProperties: nil,
      resultBundlePath: nil,
      reportActivities: false,
      coverageDirectoryPath: nil,
      enableContinuousCoverageCollection: false,
      logDirectoryPath: nil,
      reportResultBundle: false
    )

    let copy = config.copy() as! FBTestLaunchConfiguration

    XCTAssertEqual(copy.testBundle.name, config.testBundle.name)
    XCTAssertEqual(copy.testBundle.identifier, config.testBundle.identifier)
    XCTAssertEqual(copy.timeout, config.timeout)
    XCTAssertEqual(copy.shouldInitializeUITesting, config.shouldInitializeUITesting)
  }

  // MARK: FBArchitecture Constants

  func testArchitectureConstants() {
    XCTAssertEqual(FBArchitecture.I386.rawValue, "i386")
    XCTAssertEqual(FBArchitecture.X86_64.rawValue, "x86_64")
    XCTAssertEqual(FBArchitecture.armv7.rawValue, "armv7")
    XCTAssertEqual(FBArchitecture.armv7s.rawValue, "armv7s")
    XCTAssertEqual(FBArchitecture.arm64.rawValue, "arm64")
    XCTAssertEqual(FBArchitecture.arm64e.rawValue, "arm64e")
  }

  // MARK: FBCrashLog dateFormatter

  func testCrashLogDateFormatter() {
    let formatter = FBCrashLog.dateFormatter()
    XCTAssertNotNil(formatter)
  }

  // MARK: FBApplicationInstallInfoKey Constants

  func testApplicationInstallInfoKeyConstants() {
    XCTAssertEqual(FBApplicationInstallInfoKey.applicationType.rawValue, "ApplicationType")
    XCTAssertEqual(FBApplicationInstallInfoKey.bundleIdentifier.rawValue, "CFBundleIdentifier")
    XCTAssertEqual(FBApplicationInstallInfoKey.bundleName.rawValue, "CFBundleName")
    XCTAssertEqual(FBApplicationInstallInfoKey.path.rawValue, "Path")
    XCTAssertEqual(FBApplicationInstallInfoKey.signerIdentity.rawValue, "SignerIdentity")
  }
}
