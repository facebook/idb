/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Pins what `CodesignProvider` gets out of `/usr/bin/codesign`: which stream each
/// value is read from, how a non-zero exit reaches the caller, and the permission
/// fixup that runs before the tool does.
///
/// Nothing here asserts a desirable design. Each case records what callers observe
/// today so that a later replacement has to either reproduce it or change it
/// deliberately.
@Suite
struct CodesignProviderTests {

  // MARK: - Fixtures

  /// `/bin/echo` stands in for an arbitrary already-signed Mach-O. Copying it
  /// preserves Apple's signature, so a re-sign is visible as a changed CDHash
  /// rather than as the appearance of one.
  private static let machOSource = "/bin/echo"

  private static func makeTemporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("CodesignProviderTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static func writeInfoPlist(to url: URL, executableName: String) throws {
    let plist = [
      "CFBundleExecutable": executableName,
      "CFBundleIdentifier": "com.facebook.fbcontrolcore.tests.\(executableName)",
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: url)
  }

  /// An iOS-layout bundle: `Info.plist` and the executable sit at the bundle root,
  /// which is the only layout where `_CodeSignature/CodeResources` lands where
  /// `makeCodesignatureWritable` looks for it.
  private static func makeFlatBundle(in directory: URL, name: String) throws -> URL {
    let bundle = directory.appendingPathComponent("\(name).app", isDirectory: true)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try FileManager.default.copyItem(atPath: machOSource, toPath: bundle.appendingPathComponent(name).path)
    try writeInfoPlist(to: bundle.appendingPathComponent("Info.plist"), executableName: name)
    return bundle
  }

  private static func adHocProvider() -> CodesignProvider {
    CodesignProvider.codeSignCommandWithAdHocIdentity(logger: nil)
  }

  private static func posixPermissions(of path: String) throws -> Int16 {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    return (attributes[.posixPermissions] as! NSNumber).int16Value
  }

  // MARK: - Signing and reading back a hash

  @Test("An ad-hoc signature is readable back as a CDHash")
  func adHocSignatureRoundTripsThroughCdHash() async throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bundle = try Self.makeFlatBundle(in: directory, name: "RoundTrip")
    let provider = Self.adHocProvider()

    let before = try await provider.cdHashForBundle(atPath: bundle.path)
    try await provider.signBundle(atPath: bundle.path)
    let after = try await provider.cdHashForBundle(atPath: bundle.path)

    #expect(after != before, "Re-signing replaces the signature inherited from the copied binary")
    #expect(after.count == 40)
    #expect(after.allSatisfy { $0.isHexDigit && !$0.isUppercase })
  }

  @Test("The CDHash is parsed out of codesign's standard error, which is where the tool writes it")
  func cdHashIsReadFromStandardErrorRatherThanStandardOutput() async throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bundle = try Self.makeFlatBundle(in: directory, name: "Streams")
    let provider = Self.adHocProvider()
    try await provider.signBundle(atPath: bundle.path)

    // `codesign -dvvvv` writes its whole report to stderr, so a reader that took
    // the conventional stream would find nothing to match `CDHash=` against.
    let process = try await bridgeFBFuture(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/usr/bin/codesign", arguments: ["-dvvvv", bundle.path])
        .withStdOutInMemoryAsString()
        .withStdErrInMemoryAsString()
        .runUntilCompletion(withAcceptableExitCodes: [0]))

    #expect((process.stdOut as String?) == "")
    let standardError = (process.stdErr as String?) ?? ""
    #expect(standardError.contains("CDHash="))

    let cdHash = try await provider.cdHashForBundle(atPath: bundle.path)
    #expect(standardError.contains("CDHash=\(cdHash)"))
  }

  // MARK: - Failures

  @Test("A codesign failure is reported by exit code and output, not by the acceptable-exit-code check")
  func signingFailureCarriesTheExitCodeAndOutput() async throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // A directory named `.app` with no `Info.plist` is not a bundle codesign can act on.
    let bundle = directory.appendingPathComponent("Unsuitable.app", isDirectory: true)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

    do {
      try await Self.adHocProvider().signBundle(atPath: bundle.path)
      Issue.record("Expected signing an unsuitable bundle to fail")
    } catch {
      let message = error.localizedDescription
      // The provider runs codesign under an accept-anything policy and
      // re-examines the exit code itself, so a caller sees its domain error
      // rather than any generic "not acceptable" launch-layer phrasing.
      #expect(message.contains("Codesigning failed with exit code 1"))
      #expect(message.contains("bundle format unrecognized, invalid, or unsuitable"))
      #expect(!message.contains("is not acceptable"))
    }
  }

  @Test("A CDHash lookup failure is reported with its own distinct message")
  func cdHashFailureCarriesTheExitCodeAndOutput() async throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let bundle = directory.appendingPathComponent("Unsuitable.app", isDirectory: true)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

    do {
      _ = try await Self.adHocProvider().cdHashForBundle(atPath: bundle.path)
      Issue.record("Expected the CDHash lookup to fail")
    } catch {
      let message = error.localizedDescription
      #expect(message.contains("Checking CDHash of codesign execution failed 1"))
      #expect(!message.contains("is not acceptable"))
    }
  }

  // MARK: - The permission fixup

  @Test("A read-only CodeResources is made user-writable before codesign is invoked")
  func signingAddsUserWriteToAReadOnlyCodeResources() async throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // Deliberately not a signable bundle: the fixup runs first and unconditionally,
    // so the resulting codesign failure isolates the permission change from any
    // rewriting codesign would otherwise do to the same file.
    let bundle = directory.appendingPathComponent("ReadOnly.app", isDirectory: true)
    let codeResources = bundle.appendingPathComponent("_CodeSignature/CodeResources")
    try FileManager.default.createDirectory(at: codeResources.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("sealed".utf8).write(to: codeResources)
    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o444)], ofItemAtPath: codeResources.path)

    await #expect(throws: (any Error).self) {
      try await Self.adHocProvider().signBundle(atPath: bundle.path)
    }

    #expect(try Self.posixPermissions(of: codeResources.path) == 0o644)
  }
}
