/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Pins how `ArchitectureProcessAdapter` drives `lipo` and `otool`: which
/// architecture it picks, what it does with the thinned slice, and how the original
/// binary's rpaths end up in the adapted environment.
///
/// Nothing here asserts a desirable design. Each case records what callers observe
/// today so that a later replacement has to either reproduce it or change it
/// deliberately.
@Suite
struct ArchitectureProcessAdapterTests {

  // MARK: - Fixtures

  /// Xcode's macOS `xctest`, the binary the adapter exists to thin. It is fat with plain
  /// `arm64` and `x86_64` slices and carries several `@executable_path` rpaths.
  private static var fatBinary: String {
    (XcodeConfiguration.developerDirectory as NSString).appendingPathComponent("usr/bin/xctest")
  }

  private static func makeTemporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("ArchitectureProcessAdapterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static func run(_ executable: String, _ arguments: [String]) async throws -> String {
    let result = try await Subprocess(executable: executable, arguments: arguments)
      .run(output: .string, error: .closed, timeout: 10)
    return result.standardOutput
  }

  private static func architectures(of binary: String) async throws -> [String] {
    try await run("/usr/bin/lipo", ["-archs", binary]).split(whereSeparator: \.isWhitespace).map(String.init)
  }

  private static func rpaths(of binary: String) async throws -> Set<String> {
    let lines = try await run("/usr/bin/otool", ["-l", binary]).components(separatedBy: "\n")
    var rpaths = Set<String>()
    for (index, line) in lines.enumerated() where line.contains("cmd LC_RPATH") && index + 2 < lines.count {
      let fields = lines[index + 2].split(separator: " ")
      if fields.count >= 2, fields[0] == "path" {
        rpaths.insert(String(fields[1]))
      }
    }
    return rpaths
  }

  // MARK: - Architecture selection

  @Test("The host supports arm64 only")
  func hostSupportsArm64Only() {
    #expect(ArchitectureProcessAdapter.hostMachineSupportedArchitectures() == [.arm64])
  }

  @Test("Thinning fails before any tool runs when no requested architecture is supported")
  func thinningFailsWhenNoRequestedArchitectureIsSupported() async throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
      _ = try await ArchitectureProcessAdapter.thinExecutable(
        atPath: Self.fatBinary,
        toAnyArchitectureIn: [.arm64],
        hostArchitectures: [],
        temporaryDirectory: directory)
      Issue.record("Expected thinning to fail when the requested architecture is unsupported")
    } catch {
      #expect(error.localizedDescription.contains("Could not select an architecture from"))
    }

    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test("x86_64 is never selected, even when requested, supported and present in the binary")
  func x86_64IsNeverSelected() async throws {
    try #require(try await Self.architectures(of: Self.fatBinary).contains("x86_64"), "\(Self.fatBinary) must carry an x86_64 slice for this to be meaningful")

    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
      _ = try await ArchitectureProcessAdapter.thinExecutable(
        atPath: Self.fatBinary,
        toAnyArchitectureIn: [.x86_64],
        hostArchitectures: [.arm64, .x86_64],
        temporaryDirectory: directory)
      Issue.record("Expected thinning to refuse x86_64")
    } catch {
      #expect(error.localizedDescription.contains("Could not select an architecture from"))
    }

    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  // MARK: - Extraction

  @Test("The arm64 slice is thinned into the temporary directory")
  func thinningExtractsTheArm64SliceIntoTheTemporaryDirectory() async throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let thinned = try await ArchitectureProcessAdapter.thinExecutable(
      atPath: Self.fatBinary,
      toAnyArchitectureIn: [.arm64, .x86_64],
      hostArchitectures: [.arm64],
      temporaryDirectory: directory)

    let fileName = (thinned.path as NSString).lastPathComponent
    #expect((thinned.path as NSString).deletingLastPathComponent == directory.path)
    // The name is the original binary's, a UUID, and the architecture — the UUID is
    // what keeps concurrent thinnings of the same binary from colliding.
    #expect(fileName.hasPrefix("xctest"))
    #expect(fileName.hasSuffix(".arm64"))
    #expect(try await Self.architectures(of: thinned.path) == ["arm64"])
    #expect(Set(thinned.environment.keys) == ["DYLD_FRAMEWORK_PATH", "DYLD_LIBRARY_PATH"])
  }

  // MARK: - Dyld search paths

  @Test("Both dyld search paths are set from the original binary's @executable_path rpaths")
  func thinningRewritesExecutablePathRpathsIntoBothDyldSearchPaths() async throws {
    let executablePathRpaths = try await Self.rpaths(of: Self.fatBinary).filter { $0.hasPrefix("@executable_path") }
    try #require(!executablePathRpaths.isEmpty, "\(Self.fatBinary) must carry an @executable_path rpath for this to be meaningful")

    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let thinned = try await ArchitectureProcessAdapter.thinExecutable(
      atPath: Self.fatBinary,
      toAnyArchitectureIn: [.arm64],
      hostArchitectures: [.arm64],
      temporaryDirectory: directory)

    // The thinned copy lives in a temporary directory, so `@executable_path` no
    // longer resolves to anything useful. Each rpath is rewritten against the
    // original binary's folder and the result is put on both search paths, uncleaned
    // — the `..` from the load command survives into the environment.
    let binaryFolder = ((Self.fatBinary as NSString).resolvingSymlinksInPath as NSString).deletingLastPathComponent
    let expected = Set(executablePathRpaths.map { $0.replacingOccurrences(of: "@executable_path", with: binaryFolder) })
    let frameworkPath = try #require(thinned.environment["DYLD_FRAMEWORK_PATH"])
    #expect(Set(frameworkPath.components(separatedBy: ":")) == expected)
    #expect(thinned.environment["DYLD_LIBRARY_PATH"] == frameworkPath)
  }

  @Test("A binary with no rpaths still gets both dyld search paths, set to the empty string")
  func thinningSetsEmptyDyldSearchPathsForABinaryWithoutRpaths() async throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    // A copy of the fat fixture with every rpath stripped from both slices.
    let binary = directory.appendingPathComponent("norpaths").path
    try FileManager.default.copyItem(atPath: (Self.fatBinary as NSString).resolvingSymlinksInPath, toPath: binary)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary)
    let deletions = try await Self.rpaths(of: binary).flatMap { ["-delete_rpath", $0] }
    _ = try await Self.run("/usr/bin/xcrun", ["install_name_tool"] + deletions + [binary])
    try #require(try await Self.rpaths(of: binary).isEmpty)

    let thinned = try await ArchitectureProcessAdapter.thinExecutable(
      atPath: binary,
      toAnyArchitectureIn: [.arm64],
      hostArchitectures: [.arm64],
      temporaryDirectory: directory)

    // The variables are written unconditionally, so a binary with nothing to rewrite
    // is launched with two empty search paths rather than with neither variable set.
    #expect(thinned.environment["DYLD_FRAMEWORK_PATH"] == "")
    #expect(thinned.environment["DYLD_LIBRARY_PATH"] == "")
  }
}
