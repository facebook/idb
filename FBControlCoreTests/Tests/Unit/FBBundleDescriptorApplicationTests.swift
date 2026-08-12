/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import XCTest

/// Coverage for locating the single `.app` inside an extracted archive, which is
/// the step between unpacking an `.ipa` and installing what came out of it.
final class FBBundleDescriptorApplicationTests: XCTestCase {

  private var logger: FBControlCoreLoggerDouble!
  private var tempDirectory: String!

  override func setUp() {
    super.setUp()
    logger = FBControlCoreLoggerDouble()
    tempDirectory = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(
      atPath: tempDirectory,
      withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: tempDirectory)
    super.tearDown()
  }

  // MARK: - Fixtures

  private var rootURL: URL {
    URL(fileURLWithPath: tempDirectory)
  }

  private func path(_ relative: String) -> String {
    (tempDirectory as NSString).appendingPathComponent(relative)
  }

  /// Writes a loadable flat (iOS-style) app bundle. The executable is a copy of a
  /// real system binary, because `FBBundleDescriptor` parses the Mach-O header and
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
    _ actual: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(
      URL(fileURLWithPath: actual).resolvingSymlinksInPath().path,
      URL(fileURLWithPath: expected).resolvingSymlinksInPath().path,
      file: file,
      line: line)
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

  func testFindAppPath_WhenLaidOutLikeAnIPA_FindsTheApp() throws {
    let expected = try makeAppBundle("Payload/Sample.app", identifier: "com.example.sample")

    let bundle = try FBBundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)

    assertSamePath(bundle.path, expected)
    XCTAssertEqual(bundle.identifier, "com.example.sample")
    XCTAssertEqual(bundle.name, "Sample")
    XCTAssertNotNil(bundle.binary)
  }

  func testFindAppPath_WhenAppIsAtTheRoot_FindsTheApp() throws {
    let expected = try makeAppBundle("Sample.app", identifier: "com.example.sample")

    let bundle = try FBBundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)

    assertSamePath(bundle.path, expected)
  }

  func testFindAppPath_WhenAppIsDeeplyNested_FindsTheApp() throws {
    let expected = try makeAppBundle(
      "one/two/three/Sample.app", identifier: "com.example.sample")

    let bundle = try FBBundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)

    assertSamePath(bundle.path, expected)
  }

  func testFindAppPath_WhenSiblingFilesArePresent_IgnoresThem() throws {
    let expected = try makeAppBundle("Payload/Sample.app", identifier: "com.example.sample")
    try makeFile("Payload/README.txt", contents: "ignore me")
    try makeFile("iTunesMetadata.plist", contents: "ignore me too")
    try makeDirectory("Symbols")

    let bundle = try FBBundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)

    assertSamePath(bundle.path, expected)
  }

  /// An `.app` nested inside another `.app` -- the shape of a bundled app
  /// extension or watch app -- must not count as a second application. The
  /// enumerator skips the descendants of anything it already matched.
  func testFindAppPath_WhenAppContainsANestedApp_FindsOnlyTheOuterApp() throws {
    let expected = try makeAppBundle("Payload/Sample.app", identifier: "com.example.sample")
    try makeAppBundle(
      "Payload/Sample.app/Watch/Companion.app", identifier: "com.example.sample.watch")

    let bundle = try FBBundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)

    assertSamePath(bundle.path, expected)
  }

  func testFindAppPath_WhenThereAreTwoApps_Fails() throws {
    try makeAppBundle("Payload/First.app", identifier: "com.example.first")
    try makeAppBundle("Payload/Second.app", identifier: "com.example.second")

    XCTAssertThrowsError(
      try FBBundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)
    ) { error in
      let description = (error as NSError).localizedDescription
      XCTAssertTrue(
        description.contains("found 2"), "Should report the count, got: \(description)")
      XCTAssertTrue(
        description.contains("First.app"), "Should name the apps, got: \(description)")
      XCTAssertTrue(
        description.contains("Second.app"), "Should name the apps, got: \(description)")
    }
  }

  func testFindAppPath_WhenThereIsNoApp_FailsAndListsWhatWasPresent() throws {
    try makeFile("Payload/NotAnApp.txt", contents: "nope")

    XCTAssertThrowsError(
      try FBBundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)
    ) { error in
      let description = (error as NSError).localizedDescription
      XCTAssertTrue(
        description.contains("NotAnApp.txt"),
        "Should list the files it did find, got: \(description)")
    }
  }

  func testFindAppPath_WhenDirectoryIsEmpty_Fails() throws {
    XCTAssertThrowsError(try FBBundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger))
  }

  /// A plain file whose name ends in `.app` is not a bundle, so it is not a
  /// candidate at all -- the lookup fails as though the directory held no app.
  func testFindAppPath_WhenAppSuffixIsAPlainFile_Fails() throws {
    try makeFile("Payload/Sample.app", contents: "not a directory")

    XCTAssertThrowsError(try FBBundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger))
  }

  /// `isApplication` only checks the suffix and that the path is a directory, so a
  /// bundle with no `Info.plist` is selected and then fails to load. The error
  /// comes from reading the bundle, not from the search.
  func testFindAppPath_WhenAppHasNoInfoPlist_FailsLoadingTheBundle() throws {
    try makeDirectory("Payload/Sample.app")

    XCTAssertThrowsError(
      try FBBundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)
    ) { error in
      let description = (error as NSError).localizedDescription
      XCTAssertFalse(
        description.contains("Could not find an Application"),
        "Should fail loading the bundle, not searching for it, got: \(description)")
    }
  }

  func testFindAppPath_WhenAppHasNoBundleIdentifier_Fails() throws {
    let bundlePath = path("Payload/Sample.app")
    try FileManager.default.createDirectory(
      atPath: bundlePath, withIntermediateDirectories: true)
    try FileManager.default.copyItem(
      atPath: "/bin/ls", toPath: (bundlePath as NSString).appendingPathComponent("Sample"))
    let data = try PropertyListSerialization.data(
      fromPropertyList: ["CFBundleExecutable": "Sample"], format: .xml, options: 0)
    try data.write(
      to: URL(fileURLWithPath: (bundlePath as NSString).appendingPathComponent("Info.plist")))

    XCTAssertThrowsError(
      try FBBundleDescriptor.findAppPath(fromDirectory: rootURL, logger: logger)
    ) { error in
      XCTAssertTrue(
        (error as NSError).localizedDescription.contains("Bundle ID"),
        "Got: \((error as NSError).localizedDescription)")
    }
  }

  func testFindAppPath_WhenDirectoryDoesNotExist_Fails() throws {
    let absent = URL(fileURLWithPath: path("absent"))

    XCTAssertThrowsError(try FBBundleDescriptor.findAppPath(fromDirectory: absent, logger: logger))
  }

  func testFindAppPath_WithoutALogger_StillFindsTheApp() throws {
    let expected = try makeAppBundle("Payload/Sample.app", identifier: "com.example.sample")

    let bundle = try FBBundleDescriptor.findAppPath(fromDirectory: rootURL, logger: nil)

    assertSamePath(bundle.path, expected)
  }

  // MARK: - isApplication

  func testIsApplication_ForADirectoryWithTheAppSuffix_IsTrue() throws {
    try makeDirectory("Sample.app")

    XCTAssertTrue(FBBundleDescriptor.isApplication(atPath: path("Sample.app")))
  }

  func testIsApplication_ForAPlainFileWithTheAppSuffix_IsFalse() throws {
    try makeFile("Sample.app", contents: "not a directory")

    XCTAssertFalse(FBBundleDescriptor.isApplication(atPath: path("Sample.app")))
  }

  func testIsApplication_ForADirectoryWithoutTheAppSuffix_IsFalse() throws {
    try makeDirectory("Sample")

    XCTAssertFalse(FBBundleDescriptor.isApplication(atPath: path("Sample")))
  }

  func testIsApplication_ForAnAbsentPath_IsFalse() {
    XCTAssertFalse(FBBundleDescriptor.isApplication(atPath: path("absent.app")))
  }
}
