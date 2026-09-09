/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Pins how `FBArchitectureProcessAdapter` drives `lipo` and `otool`: which
/// architecture it picks, what it does with the thinned slice, and how the original
/// binary's rpaths end up in the adapted environment.
///
/// Nothing here asserts a desirable design. Each case records what callers observe
/// today so that a later replacement has to either reproduce it or change it
/// deliberately.
@Suite
struct FBArchitectureProcessAdapterTests {

  // MARK: - Fixtures

  /// A fat binary whose slices are `x86_64` and `arm64e` — notably *not* plain
  /// `arm64`. That asymmetry is what makes the adapter's architecture preference
  /// observable without a second host.
  private static let fatBinary = "/bin/echo"

  /// Fat system binaries carrying an `@executable_path` `LC_RPATH`, which is the only
  /// rpath shape the adapter rewrites. Tried in order; the first that exists is used.
  private static let fatBinariesWithExecutablePathRpaths = ["/usr/bin/xprotect", "/usr/bin/swift-inspect"]

  private static func makeTemporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("FBArchitectureProcessAdapterTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private static func configuration(launchPath: String, environment: [String: String] = [:]) -> FBProcessSpawnConfiguration {
    FBProcessSpawnConfiguration(
      launchPath: launchPath,
      arguments: ["--first", "--second"],
      environment: environment,
      io: FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull(),
      mode: .posixSpawn)
  }

  private static func architectures(of binary: String) async throws -> [String] {
    let process = try await bridgeFBFuture(
      FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath("/usr/bin/lipo", arguments: ["-archs", binary])
        .withStdOutInMemoryAsString()
        .withStdErrToDevNull()
        .runUntilCompletion(withAcceptableExitCodes: [0]))
    return ((process.stdOut as String?) ?? "").split(separator: " ").map(String.init)
  }

  // MARK: - Architecture selection

  @Test("Adaptation fails before any tool runs when no requested architecture is supported")
  func adaptationFailsWhenNoRequestedArchitectureIsSupported() async throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    do {
      _ = try await FBArchitectureProcessAdapter.adaptProcessConfiguration(
        Self.configuration(launchPath: Self.fatBinary),
        toAnyArchitectureIn: [.arm64],
        hostArchitectures: [.X86_64],
        temporaryDirectory: directory)
      Issue.record("Expected adaptation to fail when the requested architecture is unsupported")
    } catch {
      #expect(error.localizedDescription.contains("Could not select an architecture from"))
    }

    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test("arm64 is preferred over x86_64 whenever both are requested and supported")
  func arm64IsPreferredOverX86_64() async throws {
    let slices = try await Self.architectures(of: Self.fatBinary)
    try #require(slices.contains("x86_64"), "\(Self.fatBinary) must carry an x86_64 slice for this contrast to hold")
    try #require(!slices.contains("arm64"), "\(Self.fatBinary) must not carry a plain arm64 slice for this contrast to hold")

    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    // Both architectures are on offer, so arm64 wins the selection and `lipo
    // -verify_arch arm64` then fails against a binary that only has arm64e. The
    // failure is the evidence of the preference: x86_64 was available and unused.
    do {
      _ = try await FBArchitectureProcessAdapter.adaptProcessConfiguration(
        Self.configuration(launchPath: Self.fatBinary),
        toAnyArchitectureIn: [.arm64, .X86_64],
        hostArchitectures: [.arm64, .X86_64],
        temporaryDirectory: directory)
      Issue.record("Expected verification of the arm64 slice to fail")
    } catch {
      #expect(error.localizedDescription.contains("Desired architecture"))
      #expect(error.localizedDescription.contains("not found in \(Self.fatBinary) binary"))
    }

    // Take arm64 off the host and the same request succeeds on x86_64.
    let adapted = try await FBArchitectureProcessAdapter.adaptProcessConfiguration(
      Self.configuration(launchPath: Self.fatBinary),
      toAnyArchitectureIn: [.arm64, .X86_64],
      hostArchitectures: [.X86_64],
      temporaryDirectory: directory)
    #expect(try await Self.architectures(of: adapted.launchPath) == ["x86_64"])
  }

  // MARK: - Extraction

  @Test("The selected slice is thinned into the temporary directory and everything else is carried over")
  func adaptationThinsTheBinaryAndPreservesTheRestOfTheConfiguration() async throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = Self.configuration(launchPath: Self.fatBinary, environment: ["KEEP": "ME"])

    let adapted = try await FBArchitectureProcessAdapter.adaptProcessConfiguration(
      original,
      toAnyArchitectureIn: [.X86_64],
      hostArchitectures: [.X86_64],
      temporaryDirectory: directory)

    let fileName = (adapted.launchPath as NSString).lastPathComponent
    #expect((adapted.launchPath as NSString).deletingLastPathComponent == directory.path)
    // The name is the original binary's, a UUID, and the architecture — the UUID is
    // what keeps concurrent adaptations of the same binary from colliding.
    #expect(fileName.hasPrefix("echo"))
    #expect(fileName.hasSuffix(".x86_64"))
    #expect(FileManager.default.fileExists(atPath: adapted.launchPath))

    #expect(adapted.arguments == original.arguments)
    #expect(adapted.mode == original.mode)
    #expect(adapted.io === original.io)
    #expect(adapted.environment["KEEP"] == "ME")
  }

  // MARK: - Dyld search paths

  @Test("Both dyld search paths are set from the original binary's @executable_path rpaths")
  func adaptationRewritesExecutablePathRpathsIntoBothDyldSearchPaths() async throws {
    let binary = try #require(
      Self.fatBinariesWithExecutablePathRpaths.first(where: FileManager.default.fileExists(atPath:)),
      "This host has none of \(Self.fatBinariesWithExecutablePathRpaths), so there is no fat binary with an @executable_path rpath to adapt")
    try #require(try await Self.architectures(of: binary).contains("x86_64"))

    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let adapted = try await FBArchitectureProcessAdapter.adaptProcessConfiguration(
      Self.configuration(launchPath: binary),
      toAnyArchitectureIn: [.X86_64],
      hostArchitectures: [.X86_64],
      temporaryDirectory: directory)

    // The thinned copy lives in a temporary directory, so `@executable_path` no
    // longer resolves to anything useful. Each rpath is rewritten against the
    // original binary's folder and the result is put on both search paths, uncleaned
    // — the `..` from the load command survives into the environment.
    let expected = ((binary as NSString).deletingLastPathComponent as NSString).appendingPathComponent("../Frameworks")
    #expect(adapted.environment["DYLD_FRAMEWORK_PATH"] == expected)
    #expect(adapted.environment["DYLD_LIBRARY_PATH"] == expected)
  }

  @Test("A binary with no rpaths still gets both dyld search paths, set to the empty string")
  func adaptationSetsEmptyDyldSearchPathsForABinaryWithoutRpaths() async throws {
    let directory = try Self.makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let adapted = try await FBArchitectureProcessAdapter.adaptProcessConfiguration(
      Self.configuration(launchPath: Self.fatBinary),
      toAnyArchitectureIn: [.X86_64],
      hostArchitectures: [.X86_64],
      temporaryDirectory: directory)

    // The variables are written unconditionally, so a binary with nothing to rewrite
    // is launched with two empty search paths rather than with neither variable set.
    #expect(adapted.environment["DYLD_FRAMEWORK_PATH"] == "")
    #expect(adapted.environment["DYLD_LIBRARY_PATH"] == "")
  }
}
