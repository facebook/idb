/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import Foundation
import IDBGRPCSwift
import Testing

/// The REPL's check of an `Execute`'s expected build against the app it serves: the build UUID
/// the Apple prelude writes into `BuildInfo.json`, and the main executable's UUID.
@Suite
struct ReplBuildIdentityTests {

  private static let build = "4F3C2B1A-0000-4000-8000-00000000ABCD"
  private static let executable = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

  /// A bundle directory holding `BuildInfo.json` at `relativePath`, as the prelude lays it out.
  private func bundle(buildInfoAt relativePath: String?, buildUUID: String = build) throws -> String {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ReplBuildIdentityTests-\(UUID().uuidString)/App.app")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    if let relativePath {
      let file = root.appendingPathComponent(relativePath)
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONSerialization.data(withJSONObject: ["build_uuid": buildUUID]).write(to: file)
    }
    return root.path
  }

  @Test(arguments: ["BuildInfo.json", "Contents/Resources/BuildInfo.json"])
  func readsTheBuildUUIDWhereThePreludeWritesIt(relativePath: String) throws {
    let identity = ReplAppIdentity(bundlePath: try bundle(buildInfoAt: relativePath), executableUUID: Self.executable)
    #expect(identity == ReplAppIdentity(buildUUID: Self.build, executableUUID: Self.executable.uuidString))
  }

  @Test
  func aBundleWithoutTheFileHasNoBuildUUID() throws {
    let identity = ReplAppIdentity(bundlePath: try bundle(buildInfoAt: nil), executableUUID: nil)
    #expect(identity == ReplAppIdentity(buildUUID: nil, executableUUID: nil))
  }

  @Test
  func aFileWithoutTheKeyHasNoBuildUUID() throws {
    let root = try bundle(buildInfoAt: nil)
    try Data("{\"other\": 1}".utf8).write(to: URL(fileURLWithPath: root).appendingPathComponent("BuildInfo.json"))
    #expect(ReplAppIdentity.buildUUID(inBundleAt: root) == nil)
  }

  @Test
  func noExpectationIsEmptyAndAnExecuteCarriesBoth() {
    #expect(ReplBuildExpectation(Idb_ReplRequest.Execute()).isEmpty)
    var execute = Idb_ReplRequest.Execute()
    execute.expectedBuildUuid = "b"
    execute.expectedExecutableUuid = "e"
    #expect(ReplBuildExpectation(execute) == ReplBuildExpectation(buildUUID: "b", executableUUID: "e"))
  }

  @Test
  func matchingBuildIsAcceptedRegardlessOfCase() {
    let identity = ReplAppIdentity(buildUUID: Self.build, executableUUID: Self.executable.uuidString)
    #expect(ReplBuildIdentityCheck.verify(ReplBuildExpectation(buildUUID: Self.build.lowercased()), against: identity, bundleID: "com.x") == .accepted)
    #expect(
      ReplBuildIdentityCheck.verify(
        ReplBuildExpectation(buildUUID: Self.build, executableUUID: Self.executable.uuidString.lowercased()), against: identity, bundleID: "com.x") == .accepted)
  }

  @Test
  func anotherBuildIsRejectedAsAMismatchNamingBoth() {
    let identity = ReplAppIdentity(buildUUID: Self.build, executableUUID: nil)
    let verdict = ReplBuildIdentityCheck.verify(ReplBuildExpectation(buildUUID: "other"), against: identity, bundleID: "com.x")
    guard case let .rejected(rejection, message) = verdict else {
      Issue.record("expected a rejection, got \(verdict)")
      return
    }
    #expect(rejection == .buildUuidMismatch)
    #expect(message.contains(Self.build) && message.contains("other") && message.contains("com.x"))
  }

  @Test
  func aBundleWithoutABuildUUIDIsRejectedAsUnavailable() {
    let verdict = ReplBuildIdentityCheck.verify(ReplBuildExpectation(buildUUID: Self.build), against: ReplAppIdentity(buildUUID: nil, executableUUID: nil), bundleID: "com.x")
    #expect(verdict == .rejected(.buildUuidUnavailable, message: "com.x has no BuildInfo.json with a build_uuid; build the app with include_build_info_file to check its build"))
  }

  @Test
  func theExecutableIsCheckedToo() {
    let identity = ReplAppIdentity(buildUUID: Self.build, executableUUID: Self.executable.uuidString)
    let mismatch = ReplBuildIdentityCheck.verify(ReplBuildExpectation(buildUUID: Self.build, executableUUID: "other"), against: identity, bundleID: "com.x")
    guard case let .rejected(rejection, _) = mismatch else {
      Issue.record("expected a rejection, got \(mismatch)")
      return
    }
    #expect(rejection == .executableUuidMismatch)
    let unavailable = ReplBuildIdentityCheck.verify(
      ReplBuildExpectation(executableUUID: Self.executable.uuidString), against: ReplAppIdentity(buildUUID: Self.build, executableUUID: nil), bundleID: "com.x")
    #expect(unavailable == .rejected(.executableUuidUnavailable, message: "the main executable UUID of com.x could not be read"))
  }

  @Test
  func aSessionWithoutAnAppRejectsAnyExpectation() {
    let verdict = ReplBuildIdentityCheck.verify(ReplBuildExpectation(buildUUID: Self.build), against: nil, bundleID: nil)
    #expect(verdict == .rejected(.unsupportedContext, message: "this REPL session serves no app bundle, so an expected build UUID cannot be checked"))
  }
}
