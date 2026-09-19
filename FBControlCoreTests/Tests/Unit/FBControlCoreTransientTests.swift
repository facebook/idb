/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import XCTest

final class FBControlCoreTransientTests: XCTestCase {

  private func makeIO() -> FBProcessIO<AnyObject, AnyObject, AnyObject> {
    return FBProcessIO<AnyObject, AnyObject, AnyObject>(stdIn: nil, stdOut: nil, stdErr: nil)
  }

  private func makeBundle(name: String = "App", identifier: String = "com.test", path: String = "/tmp") -> BundleDescriptor {
    return BundleDescriptor(name: name, identifier: identifier, path: path, binary: nil)
  }

  private func makeAppLaunch(
    bundleID: String = "com.test.host",
    bundleName: String? = nil,
    launchMode: ApplicationLaunchMode = .failIfRunning
  ) -> ApplicationLaunchConfiguration {
    return ApplicationLaunchConfiguration(
      bundleID: bundleID,
      bundleName: bundleName,
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      io: makeIO(),
      launchMode: launchMode
    )
  }

  // MARK: - BundleDescriptor

  /// Two descriptors carrying separately parsed but equal binaries are equal.
  func testBundleDescriptorWithBinaryEquality() throws {
    let firstBinary = try BinaryDescriptor.binary(withPath: "/usr/bin/codesign")
    let secondBinary = try BinaryDescriptor.binary(withPath: "/usr/bin/codesign")

    let a = BundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: firstBinary)
    let b = BundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: secondBinary)

    XCTAssertEqual(a, b)
  }

  func testBundleDescriptorDescription() {
    let bundle = BundleDescriptor(name: "TestApp", identifier: "com.example.test", path: "/tmp/test", binary: nil)

    XCTAssertTrue(bundle.description.contains("TestApp"))
    XCTAssertTrue(bundle.description.contains("com.example.test"))
  }

  func testBundleFromInvalidPathThrows() {
    XCTAssertThrowsError(try BundleDescriptor.bundle(fromPath: "/nonexistent/path"))
  }

  // MARK: - InstalledApplication

  func testInstalledApplicationInstallTypeStringConversion() {
    let bundle = makeBundle()

    XCTAssertEqual(InstalledApplication(bundle: bundle, installType: .user, dataContainer: nil as String?).installTypeString, "user")
    XCTAssertEqual(InstalledApplication(bundle: bundle, installType: .system, dataContainer: nil as String?).installTypeString, "system")
    XCTAssertEqual(InstalledApplication(bundle: bundle, installType: .mac, dataContainer: nil as String?).installTypeString, "mac")
    XCTAssertEqual(InstalledApplication(bundle: bundle, installType: .unknown, dataContainer: nil as String?).installTypeString, "unknown")
    XCTAssertEqual(InstalledApplication(bundle: bundle, installType: .userDevelopment, dataContainer: nil as String?).installTypeString, "user_development")
    XCTAssertEqual(InstalledApplication(bundle: bundle, installType: .userEnterprise, dataContainer: nil as String?).installTypeString, "user_enterprise")
  }

  func testInstalledApplicationFromInstallTypeString() {
    let bundle = makeBundle()

    XCTAssertEqual(InstalledApplication(bundle: bundle, installTypeString: "System", signerIdentity: nil, dataContainer: nil as String?).installType, .system)
    XCTAssertEqual(InstalledApplication(bundle: bundle, installTypeString: "User", signerIdentity: nil, dataContainer: nil as String?).installType, .user)
    XCTAssertEqual(InstalledApplication(bundle: bundle, installTypeString: "mac", signerIdentity: nil, dataContainer: nil as String?).installType, .mac)
    XCTAssertEqual(InstalledApplication(bundle: bundle, installTypeString: nil, signerIdentity: nil, dataContainer: nil as String?).installType, .unknown)
  }

  func testInstalledApplicationSignerIdentityEnterprise() {
    let bundle = makeBundle()
    let app = InstalledApplication(bundle: bundle, installTypeString: "User", signerIdentity: "iPhone Distribution: Example Corp", dataContainer: nil as String?)
    XCTAssertEqual(app.installType, .userEnterprise)
  }

  func testInstalledApplicationSignerIdentityDevelopment() {
    let bundle = makeBundle()

    let devApp = InstalledApplication(bundle: bundle, installTypeString: "User", signerIdentity: "iPhone Developer: test@example.com", dataContainer: nil as String?)
    XCTAssertEqual(devApp.installType, .userDevelopment)

    let appleDevApp = InstalledApplication(bundle: bundle, installTypeString: "User", signerIdentity: "Apple Development: test@example.com", dataContainer: nil as String?)
    XCTAssertEqual(appleDevApp.installType, .userDevelopment)
  }

  func testInstalledApplicationEquality() throws {
    let binary = try BinaryDescriptor.binary(withPath: "/usr/bin/codesign")
    let bundle = BundleDescriptor(name: "App", identifier: "com.test", path: "/tmp", binary: binary)
    let a = InstalledApplication(bundle: bundle, installType: .user, dataContainer: "/data")
    let b = InstalledApplication(bundle: bundle, installType: .user, dataContainer: "/data")
    let c = InstalledApplication(bundle: bundle, installType: .system, dataContainer: "/data")

    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
  }

  /// The data container takes part in equality but deliberately not in the hash, so two
  /// applications differing only by their container are unequal yet share a hash bucket.
  func testInstalledApplicationHashIgnoresDataContainer() throws {
    let binary = try BinaryDescriptor.binary(withPath: "/usr/bin/codesign")
    let bundle = BundleDescriptor(name: "App", identifier: "com.test", path: "/tmp", binary: binary)
    let a = InstalledApplication(bundle: bundle, installType: .user, dataContainer: "/data/one")
    let b = InstalledApplication(bundle: bundle, installType: .user, dataContainer: "/data/two")

    XCTAssertNotEqual(a, b)
    XCTAssertEqual(a.hashValue, b.hashValue)
  }

  func testInstalledApplicationDescription() {
    let app = InstalledApplication(bundle: makeBundle(), installType: .user, dataContainer: "/data/container")

    XCTAssertTrue(app.description.contains("user"))
    XCTAssertTrue(app.description.contains("/data/container"))
  }

  // MARK: - RunningProcessInfo

  func testProcessInfoProcessName() {
    let info = RunningProcessInfo(processIdentifier: 1, launchPath: "/usr/bin/some_tool", arguments: [], environment: [:])
    XCTAssertEqual(info.processName, "some_tool")
  }

  func testProcessInfoEquality() {
    let a = RunningProcessInfo(processIdentifier: 10, launchPath: "/usr/bin/ls", arguments: ["-la"], environment: ["A": "B"])
    let b = RunningProcessInfo(processIdentifier: 10, launchPath: "/usr/bin/ls", arguments: ["-la"], environment: ["A": "B"])
    let c = RunningProcessInfo(processIdentifier: 11, launchPath: "/usr/bin/ls", arguments: ["-la"], environment: ["A": "B"])

    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
  }

  func testProcessInfoEqualityIgnoresEnvironment() {
    let a = RunningProcessInfo(processIdentifier: 10, launchPath: "/usr/bin/ls", arguments: [], environment: ["X": "1"])
    let b = RunningProcessInfo(processIdentifier: 10, launchPath: "/usr/bin/ls", arguments: [], environment: ["Y": "2"])

    XCTAssertEqual(a, b)
  }

  func testProcessInfoDescription() {
    let info = RunningProcessInfo(processIdentifier: 99, launchPath: "/usr/bin/ruby", arguments: [], environment: [:])
    XCTAssertTrue(info.description.contains("ruby"))
    XCTAssertTrue(info.description.contains("99"))
  }

  func testProcessInfoHash() {
    let a = RunningProcessInfo(processIdentifier: 10, launchPath: "/usr/bin/ls", arguments: ["-la"], environment: [:])
    let b = RunningProcessInfo(processIdentifier: 10, launchPath: "/usr/bin/ls", arguments: ["-la"], environment: [:])
    XCTAssertEqual(a.hash, b.hash)
  }

  // MARK: - ApplicationLaunchConfiguration

  func testApplicationLaunchConfigurationEquality() {
    let io = makeIO()
    let a = ApplicationLaunchConfiguration(bundleID: "com.app", bundleName: "App", arguments: [], environment: [:], waitForDebugger: false, io: io, launchMode: .failIfRunning)
    let b = ApplicationLaunchConfiguration(bundleID: "com.app", bundleName: "App", arguments: [], environment: [:], waitForDebugger: false, io: io, launchMode: .failIfRunning)

    XCTAssertEqual(a, b)
  }

  func testApplicationLaunchConfigurationInequalityByMode() {
    let a = makeAppLaunch(launchMode: .failIfRunning)
    let b = makeAppLaunch(launchMode: .relaunchIfRunning)

    XCTAssertNotEqual(a, b)
  }

  func testApplicationLaunchConfigurationDescription() {
    let config = ApplicationLaunchConfiguration(
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

  // MARK: - ProcessSpawnConfiguration

  func testProcessSpawnConfigurationProcessName() {
    let config = ProcessSpawnConfiguration(
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
    let a = ProcessSpawnConfiguration(launchPath: "/usr/bin/env", arguments: ["a"], environment: ["K": "V"], io: io, mode: .posixSpawn)
    let b = ProcessSpawnConfiguration(launchPath: "/usr/bin/env", arguments: ["a"], environment: ["K": "V"], io: io, mode: .posixSpawn)

    XCTAssertEqual(a, b)
  }

  func testProcessSpawnConfigurationInequalityByMode() {
    let io = makeIO()
    let a = ProcessSpawnConfiguration(launchPath: "/usr/bin/env", arguments: [], environment: [:], io: io, mode: .posixSpawn)
    let b = ProcessSpawnConfiguration(launchPath: "/usr/bin/env", arguments: [], environment: [:], io: io, mode: .launchd)

    XCTAssertNotEqual(a, b)
  }

  func testProcessSpawnConfigurationDescription() {
    let config = ProcessSpawnConfiguration(
      launchPath: "/usr/bin/env",
      arguments: ["--help"],
      environment: [:],
      io: makeIO(),
      mode: .default
    )

    XCTAssertTrue(config.description.contains("/usr/bin/env"))
  }

  // MARK: - CollectionInformation

  func testOneLineDescriptionFromArray() {
    let result = CollectionInformation.oneLineDescription(from: ["alpha", "beta", "gamma"])
    XCTAssertEqual(result, "[alpha, beta, gamma]")
  }

  func testOneLineDescriptionFromEmptyArray() {
    let result = CollectionInformation.oneLineDescription(from: [])
    XCTAssertEqual(result, "[]")
  }

  func testOneLineDescriptionFromDictionary() {
    let result = CollectionInformation.oneLineDescription(from: ["key": "value"])
    XCTAssertTrue(result.contains("key => value"))
    XCTAssertTrue(result.hasPrefix("{"))
    XCTAssertTrue(result.hasSuffix("}"))
  }

  func testOneLineDescriptionFromEmptyDictionary() {
    let result = CollectionInformation.oneLineDescription(from: [:])
    XCTAssertEqual(result, "{}")
  }

  func testIsArrayHeterogeneousWithMatchingClass() {
    XCTAssertTrue(CollectionInformation.isArrayHeterogeneous(["a", "b", "c"], with: NSString.self))
  }

  func testIsArrayHeterogeneousWithMismatchedClass() {
    let mixed: [Any] = ["a", NSNumber(value: 1), "b"]
    XCTAssertFalse(CollectionInformation.isArrayHeterogeneous(mixed as [AnyObject], with: NSString.self))
  }

  func testIsArrayHeterogeneousWithEmptyArray() {
    XCTAssertTrue(CollectionInformation.isArrayHeterogeneous([], with: NSString.self))
  }

  func testIsDictionaryHeterogeneousWithMatchingClasses() {
    let dict: NSDictionary = ["a": "b", "c": "d"]
    XCTAssertTrue(CollectionInformation.isDictionaryHeterogeneous(dict as! [AnyHashable: Any], keyClass: NSString.self, valueClass: NSString.self))
  }

  func testIsDictionaryHeterogeneousWithMismatchedValues() {
    let dict: NSDictionary = ["a": "b", "c": NSNumber(value: 1)]
    XCTAssertFalse(CollectionInformation.isDictionaryHeterogeneous(dict as! [AnyHashable: Any], keyClass: NSString.self, valueClass: NSString.self))
  }

  // MARK: - CollectionOperations

  func testArrayFromIndices() {
    var indexSet = IndexSet()
    indexSet.insert(1)
    indexSet.insert(3)
    indexSet.insert(5)
    let result = CollectionOperations.array(from: indexSet)
    XCTAssertEqual(result, [1, 3, 5] as [NSNumber])
  }

  func testIndicesFromArray() {
    let result = CollectionOperations.indices(from: [2, 4, 6]) as IndexSet
    var expected = IndexSet()
    expected.insert(2)
    expected.insert(4)
    expected.insert(6)
    XCTAssertEqual(result, expected)
  }

  func testArrayFromIndicesRoundTrip() {
    let original: [NSNumber] = [0, 10, 20]
    let indexSet = CollectionOperations.indices(from: original)
    let roundTripped = CollectionOperations.array(from: indexSet)
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
    let result = CollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: input)

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
    let result = CollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: input)

    XCTAssertEqual(result.count, 3)
    XCTAssertEqual(result[0] as? String, "hello")
    XCTAssertEqual(result[1] as? Int, 42)
    XCTAssertNotNil(result[2] as? [String: String])
  }

  func testNullableValueForDictionaryReturnsValue() {
    let dict: NSDictionary = ["key": "value"]
    let result = CollectionOperations.nullableValue(for: dict as! [AnyHashable: Any], key: "key" as NSString)
    XCTAssertEqual(result as? String, "value")
  }

  func testNullableValueForDictionaryReturnsNilForNSNull() {
    let dict: NSDictionary = ["key": NSNull()]
    let result = CollectionOperations.nullableValue(for: dict as! [AnyHashable: Any], key: "key" as NSString)
    XCTAssertNil(result)
  }

  func testNullableValueForDictionaryReturnsNilForMissingKey() {
    let dict: NSDictionary = ["key": "value"]
    let result = CollectionOperations.nullableValue(for: dict as! [AnyHashable: Any], key: "missing" as NSString)
    XCTAssertNil(result)
  }

  func testArrayWithObjectCount() {
    let result = CollectionOperations.array(with: "x", count: 3)
    XCTAssertEqual(result.count, 3)
    for item in result {
      XCTAssertEqual(item as? String, "x")
    }
  }

  func testArrayWithObjectCountZero() {
    let result = CollectionOperations.array(with: "x", count: 0)
    XCTAssertEqual(result.count, 0)
  }
}
