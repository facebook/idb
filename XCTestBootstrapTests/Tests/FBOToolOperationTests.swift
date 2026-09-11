/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import XCTest
@testable import XCTestBootstrap

/// Pins how `FBOToolOperation` resolves a bundle to an executable and what it makes
/// of `otool -L`'s output, including the case where the tool reports a problem but
/// still exits successfully.
///
/// Nothing here asserts a desirable design. Each case records what callers observe
/// today so that a later replacement has to either reproduce it or change it
/// deliberately.
final class FBOToolOperationTests: XCTestCase {

  private var temporaryDirectory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("FBOToolOperationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: temporaryDirectory)
    temporaryDirectory = nil
    try super.tearDownWithError()
  }

  // MARK: - Helpers

  private func makeMacBundle(named name: String, executable: Data?) throws -> URL {
    let bundle = temporaryDirectory.appendingPathComponent("\(name).bundle", isDirectory: true)
    let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

    var plist = ["CFBundleIdentifier": "com.facebook.xctestbootstrap.tests.\(name)"]
    if let executable {
      let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
      try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
      try executable.write(to: macOS.appendingPathComponent(name))
      plist["CFBundleExecutable"] = name
    }
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
    return bundle
  }

  private func listSanitiserDylibs(byBundle path: String) async throws -> [String] {
    try await FBOToolOperation.listSanitiserDylibsRequired(byBundle: path)
  }

  // MARK: - Bundle resolution

  func testAMissingPathIsRejectedAsNotABundle() async throws {
    let path = temporaryDirectory.appendingPathComponent("Absent.xctest").path

    do {
      _ = try await listSanitiserDylibs(byBundle: path)
      XCTFail("Expected a missing path to be rejected")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("does not identify an accessible bundle directory."), error.localizedDescription)
    }
  }

  func testARegularFileIsRejectedAsNotABundle() async throws {
    let path = temporaryDirectory.appendingPathComponent("NotADirectory.xctest").path
    try Data("plain".utf8).write(to: URL(fileURLWithPath: path))

    do {
      _ = try await listSanitiserDylibs(byBundle: path)
      XCTFail("Expected a regular file to be rejected")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("does not identify an accessible bundle directory."), error.localizedDescription)
    }
  }

  func testABundleWithoutAnExecutableIsRejected() async throws {
    let bundle = try makeMacBundle(named: "NoExecutable", executable: nil)

    // The directory is a bundle as far as `Bundle(path:)` is concerned; it is the
    // second guard, on `executablePath`, that rejects it.
    XCTAssertNotNil(Bundle(path: bundle.path))
    XCTAssertNil(Bundle(path: bundle.path)?.executablePath)

    do {
      _ = try await listSanitiserDylibs(byBundle: bundle.path)
      XCTFail("Expected a bundle with no executable to be rejected")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("does not contain an executable."), error.localizedDescription)
    }
  }

  // MARK: - otool output

  func testABundleLinkingNoSanitisersRequiresNoDylibs() async throws {
    let bundle = Self.macUnitTestBundleFixture()

    let dylibs = try await listSanitiserDylibs(byBundle: bundle.bundlePath)

    XCTAssertEqual(dylibs, [])
  }

  func testANonMachOExecutableRequiresNoDylibsBecauseOtoolStillSucceeds() async throws {
    let bundle = try makeMacBundle(named: "NotMachO", executable: Data("#!/bin/sh\nexit 0\n".utf8))

    // `otool -L` prints "is not an object file" and exits 0, so the `[0]` acceptable
    // exit code lets it through and the empty match set reads as "no sanitisers"
    // rather than as "could not tell".
    let dylibs = try await listSanitiserDylibs(byBundle: bundle.path)

    XCTAssertEqual(dylibs, [])
  }
}
