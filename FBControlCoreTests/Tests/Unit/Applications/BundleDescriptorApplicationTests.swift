/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import Testing

@Suite
final class BundleDescriptorApplicationTests {

  private let logger = ControlCoreLoggerDouble()
  private let tempDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)

  init() {
    try? FileManager.default.createDirectory(
      atPath: tempDirectory,
      withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(atPath: tempDirectory)
  }

  // MARK: - Fixtures

  private var rootURL: URL {
    URL(fileURLWithPath: tempDirectory)
  }

  private func path(_ relative: String) -> String {
    (tempDirectory as NSString).appendingPathComponent(relative)
  }

  /// Writes a loadable flat (iOS-style) app bundle. The executable is a copy of a
  /// real system binary, because `BundleDescriptor` parses the Mach-O header and
  /// a placeholder file would fail to load rather than exercising the lookup.
  @discardableResult
  private func makeAppBundle(_ relative: String, identifier: String) throws -> String {
    let bundlePath = path(relative)
    try FileManager.default.createDirectory(
      atPath: bundlePath, withIntermediateDirectories: true)
    let executableName =
      ((bundlePath as NSString).lastPathComponent as NSString).deletingPathExtension
    try FileManager.default.copyItem(
      atPath: "/bin/ls",
      toPath: (bundlePath as NSString).appendingPathComponent(executableName))
    let info: [String: Any] = [
      "CFBundleIdentifier": identifier,
      "CFBundleExecutable": executableName,
      "CFBundleName": executableName,
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: info, format: .xml, options: 0)
    try data.write(
      to: URL(fileURLWithPath: (bundlePath as NSString).appendingPathComponent("Info.plist")))
    return bundlePath
  }

  /// The temporary directory sits under `/var`, a symlink to `/private/var`, and
  /// the directory enumerator reports the resolved form. Canonicalise both sides
  /// rather than assuming which spelling comes back.
  private func assertSamePath(
    _ actual: String, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation
  ) {
    #expect(URL(fileURLWithPath: actual).resolvingSymlinksInPath().path == URL(fileURLWithPath: expected).resolvingSymlinksInPath().path, sourceLocation: sourceLocation)
  }

  private func makeDirectory(_ relative: String) throws {
    try FileManager.default.createDirectory(
      atPath: path(relative), withIntermediateDirectories: true)
  }

  private func makeFile(_ relative: String, contents: String = "") throws {
    let filePath = path(relative)
    try FileManager.default.createDirectory(
      atPath: (filePath as NSString).deletingLastPathComponent,
      withIntermediateDirectories: true)
    try contents.write(toFile: filePath, atomically: true, encoding: .utf8)
  }

  // MARK: - findAppPath

  @Test
  func findAppPath_WhenLaidOutLikeAnIPA_FindsTheApp() throws {
    let expected = try makeAppBundle("Payload/Sample.app", identifier: "com.example.sample")

    let bundle = try BundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)

    assertSamePath(bundle.path, expected)
    #expect(bundle.identifier == "com.example.sample")
    #expect(bundle.name == "Sample")
    #expect(bundle.binary != nil)
  }

  @Test
  func findAppPath_WhenAppIsAtTheRoot_FindsTheApp() throws {
    let expected = try makeAppBundle("Sample.app", identifier: "com.example.sample")

    let bundle = try BundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)

    assertSamePath(bundle.path, expected)
  }

  @Test
  func findAppPath_WhenAppIsDeeplyNested_FindsTheApp() throws {
    let expected = try makeAppBundle(
      "one/two/three/Sample.app", identifier: "com.example.sample")

    let bundle = try BundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)

    assertSamePath(bundle.path, expected)
  }

  @Test
  func findAppPath_WhenSiblingFilesArePresent_IgnoresThem() throws {
    let expected = try makeAppBundle("Payload/Sample.app", identifier: "com.example.sample")
    try makeFile("Payload/README.txt", contents: "ignore me")
    try makeFile("iTunesMetadata.plist", contents: "ignore me too")
    try makeDirectory("Symbols")

    let bundle = try BundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)

    assertSamePath(bundle.path, expected)
  }

  /// App extensions and watch apps nest an `.app` inside the `.app`; only the outer one is a candidate.
  @Test
  func findAppPath_WhenAppContainsANestedApp_FindsOnlyTheOuterApp() throws {
    let expected = try makeAppBundle("Payload/Sample.app", identifier: "com.example.sample")
    try makeAppBundle(
      "Payload/Sample.app/Watch/Companion.app", identifier: "com.example.sample.watch")

    let bundle = try BundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)

    assertSamePath(bundle.path, expected)
  }

  @Test
  func findAppPath_WhenThereAreTwoApps_Fails() throws {
    try makeAppBundle("Payload/First.app", identifier: "com.example.first")
    try makeAppBundle("Payload/Second.app", identifier: "com.example.second")

    let error = #expect(throws: (any Error).self) { try BundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger) }
    if let error {
      let description = (error as NSError).localizedDescription
      #expect(description.contains("found 2"), "Should report the count, got: \(description)")
      #expect(description.contains("First.app"), "Should name the apps, got: \(description)")
      #expect(description.contains("Second.app"), "Should name the apps, got: \(description)")
    }
  }

  @Test
  func findAppPath_WhenThereIsNoApp_FailsAndListsWhatWasPresent() throws {
    try makeFile("Payload/NotAnApp.txt", contents: "nope")

    let error = #expect(throws: (any Error).self) { try BundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger) }
    if let error {
      let description = (error as NSError).localizedDescription
      #expect(description.contains("NotAnApp.txt"), "Should list the files it did find, got: \(description)")
    }
  }

  @Test
  func findAppPath_WhenDirectoryIsEmpty_Fails() throws {
    #expect(throws: (any Error).self) { try BundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger) }
  }

  @Test
  func findAppPath_WhenAppSuffixIsAPlainFile_Fails() throws {
    try makeFile("Payload/Sample.app", contents: "not a directory")

    #expect(throws: (any Error).self) { try BundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger) }
  }

  /// `isApplication` only checks the suffix and that the path is a directory, so a
  /// bundle with no `Info.plist` is selected and then fails to load. The error
  /// comes from reading the bundle, not from the search.
  @Test
  func findAppPath_WhenAppHasNoInfoPlist_FailsLoadingTheBundle() throws {
    try makeDirectory("Payload/Sample.app")

    let error = #expect(throws: (any Error).self) { try BundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger) }
    if let error {
      let description = (error as NSError).localizedDescription
      #expect(!(description.contains("Could not find an Application")), "Should fail loading the bundle, not searching for it, got: \(description)")
    }
  }

  @Test
  func findAppPath_WhenAppHasNoBundleIdentifier_Fails() throws {
    let bundlePath = path("Payload/Sample.app")
    try FileManager.default.createDirectory(
      atPath: bundlePath, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
      atPath: "/bin/ls", toPath: (bundlePath as NSString).appendingPathComponent("Sample"))
    let data = try PropertyListSerialization.data(
      fromPropertyList: ["CFBundleExecutable": "Sample"], format: .xml, options: 0)
    try data.write(
      to: URL(fileURLWithPath: (bundlePath as NSString).appendingPathComponent("Info.plist")))

    let error = #expect(throws: (any Error).self) { try BundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger) }
    if let error {
      #expect((error as NSError).localizedDescription.contains("Bundle ID"), "Got: \((error as NSError).localizedDescription)")
    }
  }

  @Test
  func findAppPath_WhenDirectoryDoesNotExist_Fails() throws {
    let absent = URL(fileURLWithPath: path("absent"))

    #expect(throws: (any Error).self) { try BundleDescriptor.findAppPath(fromDirectory: absent, logger: logger) }
  }

  @Test
  func findAppPath_WithoutALogger_StillFindsTheApp() throws {
    let expected = try makeAppBundle("Payload/Sample.app", identifier: "com.example.sample")

    let bundle = try BundleDescriptor.findAppPath(fromDirectory: rootURL, logger: nil)

    assertSamePath(bundle.path, expected)
  }

  // MARK: - isApplication

  @Test
  func isApplication_ForADirectoryWithTheAppSuffix_IsTrue() throws {
    try makeDirectory("Sample.app")

    #expect(BundleDescriptor.isApplication(atPath: path("Sample.app")))
  }

  @Test
  func isApplication_ForAPlainFileWithTheAppSuffix_IsFalse() throws {
    try makeFile("Sample.app", contents: "not a directory")

    #expect(!(BundleDescriptor.isApplication(atPath: path("Sample.app"))))
  }

  @Test
  func isApplication_ForADirectoryWithoutTheAppSuffix_IsFalse() throws {
    try makeDirectory("Sample")

    #expect(!(BundleDescriptor.isApplication(atPath: path("Sample"))))
  }

  @Test
  func isApplication_ForAnAbsentPath_IsFalse() {
    #expect(!(BundleDescriptor.isApplication(atPath: path("absent.app"))))
  }
}
