/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
@testable import SimulatorXCTest
import Testing

/// Coverage of the REPL error descriptions. These strings are the only thing a
/// user sees when a session fails to start, so each is pinned to keep it naming
/// the thing that went wrong rather than an internal detail.
@Suite
struct SimulatorReplErrorTests {

  @Test
  func bundledResourceMissingNamesTheItem() throws {
    let message = try #require(
      SimulatorReplError.bundledResourceMissing(item: "libRepl-iOS.dylib").errorDescription)
    #expect(message.contains("libRepl-iOS.dylib"))
  }

  @Test
  func socketDirectoryCreationFailedNamesThePath() throws {
    let message = try #require(
      SimulatorReplError.socketDirectoryCreationFailed(path: "/tmp/idb_repl_501").errorDescription)
    #expect(message.contains("/tmp/idb_repl_501"))
  }

  // MARK: - targetIsNotALaunchableApp

  @Test
  func notALaunchableAppNamesTheBundleIDAndProcess() throws {
    let message = try #require(
      SimulatorReplError
        .targetIsNotALaunchableApp(bundleID: "com.apple.springboard", processIdentifier: 53_820)
        .errorDescription)
    #expect(message.contains("com.apple.springboard"))
    #expect(message.contains("53820"))
  }

  @Test
  func notALaunchableAppExplainsTheCauseAndTheRemedy() throws {
    // The whole point of this error is that the previous behaviour -- waiting out
    // the client's deadline and then reporting a hashed socket path -- told the
    // reader neither what had failed nor what to do instead.
    let message = try #require(
      SimulatorReplError
        .targetIsNotALaunchableApp(bundleID: "com.apple.springboard", processIdentifier: 1)
        .errorDescription)
    #expect(message.contains("launchd"))
    #expect(message.contains("never injected"))
    #expect(message.contains("Target an app bundle instead."))
  }

  @Test
  func notALaunchableAppIsASingleLine() throws {
    // It is rendered into a gRPC status message, where embedded newlines are unreadable.
    let message = try #require(
      SimulatorReplError
        .targetIsNotALaunchableApp(bundleID: "com.apple.springboard", processIdentifier: 1)
        .errorDescription)
    #expect(!message.contains("\n"))
  }
}
