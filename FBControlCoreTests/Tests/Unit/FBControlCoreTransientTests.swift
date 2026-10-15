/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite
struct FBControlCoreTransientTests {

  private func makeBundle(name: String = "App", identifier: String = "com.test", path: String = "/tmp") -> BundleDescriptor {
    return BundleDescriptor(name: name, identifier: identifier, path: path, binary: nil)
  }

  // MARK: - BundleDescriptor

  /// Two descriptors carrying separately parsed but equal binaries are equal.
  @Test
  func bundleDescriptorWithBinaryEquality() throws {
    let firstBinary = try BinaryDescriptor(path: "/usr/bin/codesign")
    let secondBinary = try BinaryDescriptor(path: "/usr/bin/codesign")

    let a = BundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: firstBinary)
    let b = BundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: secondBinary)

    #expect(a == b)
  }

  @Test
  func bundleDescriptorEqualityComparesEveryField() throws {
    let binary = try BinaryDescriptor(path: "/usr/bin/codesign")
    let otherBinary = try BinaryDescriptor(path: "/usr/bin/true")
    let base = BundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: binary)

    #expect(base == BundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: binary))
    #expect(base != BundleDescriptor(name: "Other", identifier: "com.test", path: "/a", binary: binary))
    #expect(base != BundleDescriptor(name: "App", identifier: "com.other", path: "/a", binary: binary))
    #expect(base != BundleDescriptor(name: "App", identifier: "com.test", path: "/b", binary: binary))
    #expect(base != BundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: otherBinary))
    #expect(base != BundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: nil))
  }

  @Test
  func bundleDescriptorEqualDescriptorsHashEqually() throws {
    let a = BundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: try BinaryDescriptor(path: "/usr/bin/codesign"))
    let b = BundleDescriptor(name: "App", identifier: "com.test", path: "/a", binary: try BinaryDescriptor(path: "/usr/bin/codesign"))
    let c = BundleDescriptor(name: "App", identifier: "com.test", path: "/c", binary: nil)

    #expect(a.hashValue == b.hashValue)
    #expect(Set([a, b, c]).count == 2)
  }

  @Test
  func bundleDescriptorDescription() {
    let bundle = BundleDescriptor(name: "TestApp", identifier: "com.example.test", path: "/tmp/test", binary: nil)

    #expect(bundle.description.contains("TestApp"))
    #expect(bundle.description.contains("com.example.test"))
  }

  @Test
  func bundleFromInvalidPathThrows() {
    #expect(throws: (any Error).self) { try BundleDescriptor.bundle(fromPath: "/nonexistent/path") }
  }

  // MARK: - InstalledApplication

  @Test
  func installedApplicationInstallTypeStringConversion() {
    let bundle = makeBundle()

    #expect(InstalledApplication(bundle: bundle, installType: .user, dataContainer: nil as String?).installTypeString == "user")
    #expect(InstalledApplication(bundle: bundle, installType: .system, dataContainer: nil as String?).installTypeString == "system")
    #expect(InstalledApplication(bundle: bundle, installType: .mac, dataContainer: nil as String?).installTypeString == "mac")
    #expect(InstalledApplication(bundle: bundle, installType: .unknown, dataContainer: nil as String?).installTypeString == "unknown")
    #expect(InstalledApplication(bundle: bundle, installType: .userDevelopment, dataContainer: nil as String?).installTypeString == "user_development")
    #expect(InstalledApplication(bundle: bundle, installType: .userEnterprise, dataContainer: nil as String?).installTypeString == "user_enterprise")
  }

  @Test
  func installedApplicationFromInstallTypeString() {
    let bundle = makeBundle()

    #expect(InstalledApplication(bundle: bundle, installTypeString: "System", signerIdentity: nil, dataContainer: nil as String?).installType == .system)
    #expect(InstalledApplication(bundle: bundle, installTypeString: "User", signerIdentity: nil, dataContainer: nil as String?).installType == .user)
    #expect(InstalledApplication(bundle: bundle, installTypeString: "mac", signerIdentity: nil, dataContainer: nil as String?).installType == .mac)
    #expect(InstalledApplication(bundle: bundle, installTypeString: nil, signerIdentity: nil, dataContainer: nil as String?).installType == .unknown)
  }

  @Test
  func installedApplicationSignerIdentityEnterprise() {
    let bundle = makeBundle()
    let app = InstalledApplication(bundle: bundle, installTypeString: "User", signerIdentity: "iPhone Distribution: Example Corp", dataContainer: nil as String?)
    #expect(app.installType == .userEnterprise)
  }

  @Test
  func installedApplicationSignerIdentityDevelopment() {
    let bundle = makeBundle()

    let devApp = InstalledApplication(bundle: bundle, installTypeString: "User", signerIdentity: "iPhone Developer: test@example.com", dataContainer: nil as String?)
    #expect(devApp.installType == .userDevelopment)

    let appleDevApp = InstalledApplication(bundle: bundle, installTypeString: "User", signerIdentity: "Apple Development: test@example.com", dataContainer: nil as String?)
    #expect(appleDevApp.installType == .userDevelopment)
  }

  @Test
  func installedApplicationEquality() throws {
    let binary = try BinaryDescriptor(path: "/usr/bin/codesign")
    let bundle = BundleDescriptor(name: "App", identifier: "com.test", path: "/tmp", binary: binary)
    let a = InstalledApplication(bundle: bundle, installType: .user, dataContainer: "/data")
    let b = InstalledApplication(bundle: bundle, installType: .user, dataContainer: "/data")
    let c = InstalledApplication(bundle: bundle, installType: .system, dataContainer: "/data")

    #expect(a == b)
    #expect(a != c)
  }

  /// The data container takes part in equality but deliberately not in the hash, so two
  /// applications differing only by their container are unequal yet share a hash bucket.
  @Test
  func installedApplicationHashIgnoresDataContainer() throws {
    let binary = try BinaryDescriptor(path: "/usr/bin/codesign")
    let bundle = BundleDescriptor(name: "App", identifier: "com.test", path: "/tmp", binary: binary)
    let a = InstalledApplication(bundle: bundle, installType: .user, dataContainer: "/data/one")
    let b = InstalledApplication(bundle: bundle, installType: .user, dataContainer: "/data/two")

    #expect(a != b)
    #expect(a.hashValue == b.hashValue)
  }

  @Test
  func installedApplicationDescription() {
    let app = InstalledApplication(bundle: makeBundle(), installType: .user, dataContainer: "/data/container")

    #expect(app.description.contains("user"))
    #expect(app.description.contains("/data/container"))
  }

  // MARK: - RunningProcessInfo

  @Test
  func processInfoProcessName() {
    let info = RunningProcessInfo(processIdentifier: 1, launchPath: "/usr/bin/some_tool", arguments: [], environment: [:])
    #expect(info.processName == "some_tool")
  }

  @Test
  func processInfoDescription() {
    let info = RunningProcessInfo(processIdentifier: 99, launchPath: "/usr/bin/ruby", arguments: [], environment: [:])
    #expect(info.description.contains("ruby"))
    #expect(info.description.contains("99"))
  }

  // MARK: - ApplicationLaunchConfiguration

  @Test
  func applicationLaunchConfigurationDescription() {
    let config = ApplicationLaunchConfiguration(
      bundleID: "com.example.app",
      bundleName: "MyApp",
      arguments: [],
      environment: [:],
      waitForDebugger: false,
      launchMode: .failIfRunning
    )

    #expect(config.description.contains("com.example.app"))
    #expect(config.description.contains("MyApp"))
  }

  // MARK: - CollectionInformation

  @Test
  func oneLineDescriptionFromArray() {
    let result = CollectionInformation.oneLineDescription(from: ["alpha", "beta", "gamma"])
    #expect(result == "[alpha, beta, gamma]")
  }

  @Test
  func oneLineDescriptionFromEmptyArray() {
    let result = CollectionInformation.oneLineDescription(from: [])
    #expect(result == "[]")
  }

  @Test
  func oneLineDescriptionFromDictionary() {
    let result = CollectionInformation.oneLineDescription(from: ["key": "value"])
    #expect(result.contains("key => value"))
    #expect(result.hasPrefix("{"))
    #expect(result.hasSuffix("}"))
  }

  @Test
  func oneLineDescriptionFromEmptyDictionary() {
    let result = CollectionInformation.oneLineDescription(from: [:])
    #expect(result == "{}")
  }

}
