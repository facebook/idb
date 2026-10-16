/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
@testable import FBSimulatorControl
@testable import FBSimulatorServices
import Foundation
import Testing

@Suite
final class SimulatorFrameworkBridgeTests {

  private let directory: URL
  private let bundledGuestPath: String

  /// A stand-in for the guest shipped in the companion's `Resources`.
  ///
  /// The contents do not matter — nothing here runs it. What matters is that it is a real file
  /// in a directory this test owns, so an assertion about what sits beside it is an assertion
  /// about what the resolver put there.
  init() throws {
    directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let guestURL = directory.appendingPathComponent("SimulatorFrameworkBridge-iOS")
    try Data("guest".utf8).write(to: guestURL)
    bundledGuestPath = guestURL.path
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  private var stagingDirectory: URL {
    directory.appendingPathComponent("staging")
  }

  private func staged(_ bundleIdentity: String) throws -> String {
    try SimulatorFrameworkBridgeStaging.stagedExecutablePath(
      bundledGuestPath: bundledGuestPath,
      bundleIdentity: bundleIdentity,
      stagingDirectory: stagingDirectory)
  }

  @Test
  func aStagedGuestIsACopyOfTheBundledGuest() throws {
    let launched = try staged("com.apple.news")
    #expect(launched != bundledGuestPath)
    #expect(
      URL(fileURLWithPath: launched).lastPathComponent == URL(fileURLWithPath: bundledGuestPath).lastPathComponent)
    #expect(
      FileManager.default.contents(atPath: launched) == FileManager.default.contents(atPath: bundledGuestPath))
    // `proc_pidpath` resolves a symlink back to the bundled guest, whose directory names no app.
    let type = try FileManager.default.attributesOfItem(atPath: launched)[.type] as? FileAttributeType
    #expect(type == .typeRegular)
  }

  @Test
  func aStagedGuestLaunchesWithTheTargetAppsBundleIdentity() throws {
    let launched = try staged("com.apple.news")
    let siblingInfoPlist = URL(fileURLWithPath: launched)
      .deletingLastPathComponent()
      .appendingPathComponent("Info.plist")
    let info = try #require(NSDictionary(contentsOf: siblingInfoPlist) as? [String: String])
    #expect(info["CFBundleIdentifier"] == "com.apple.news")
    // The lookup is rejected unless this names the executable it sits beside.
    #expect(info["CFBundleExecutable"] == URL(fileURLWithPath: launched).lastPathComponent)
  }

  /// The identity is written beside the executable, so two target apps cannot share one.
  @Test
  func eachTargetAppLaunchesItsOwnGuest() throws {
    #expect(try staged("com.apple.news") != staged("com.apple.weather"))
  }

  @Test
  func onlyABundleIdentifierCanBeStagedAsAnIdentity() {
    #expect(SimulatorFrameworkBridgeStaging.bundleIdentity("com.apple.news") == "com.apple.news")
    for bundleID in ["", ".", "..", "../news", "com/apple"] {
      #expect(SimulatorFrameworkBridgeStaging.bundleIdentity(bundleID) == nil, "\(bundleID)")
    }
  }

  @Test
  func deliveredNotificationCommandsAreStaged() {
    #expect(BridgeCommand.notifications(.delivered(bundleID: "com.apple.news")).route == .staged(bundleIdentity: "com.apple.news"))
    #expect(BridgeCommand.notifications(.clearDelivered(bundleID: "com.apple.news")).route == .staged(bundleIdentity: "com.apple.news"))
  }

  @Test
  func commandsWithoutAnIdentityUseThePersistentGuest() {
    for command: BridgeCommand in [.notifications(.list(bundleID: "com.apple.news")), .notifications(.delivered(bundleID: "../news")), .clearPhotos, .accessibility(.displays)] {
      #expect(command.route == .persistent, "\(command)")
    }
  }

  @Test
  func commandsAreDescribedAsTheirPositionalServiceAndAction() {
    #expect(BridgeCommand.dns(.set(servers: ["1.1.1.1"])).serviceAndAction == "dns set")
    #expect(BridgeCommand.notifications(.clearDelivered(bundleID: "com.apple.news")).serviceAndAction == "notifications clear-delivered")
    #expect(BridgeCommand.health(.approve(bundleID: "com.apple.news", typeIDs: [])).serviceAndAction == "health approve")
    #expect(BridgeCommand.accessibility(.hitTest(x: 1, y: 2, attributes: nil, clientType: .noClient)).serviceAndAction == "accessibility hittest")
  }

  @Test
  func failuresNameTheCommandRatherThanTheAccessibilityReader() {
    #expect(
      SimulatorFrameworkBridgeError.commandFailed(command: "dns set", exitCode: 1, output: "").localizedDescription == "SimulatorFrameworkBridge dns set failed with exit code 1: no output")
    #expect(
      SimulatorFrameworkBridgeError.transportFailed(command: "dns set", reason: "serve socket closed by peer").localizedDescription == "SimulatorFrameworkBridge dns set did not complete: serve socket closed by peer")
  }

  @Test
  func failureDetailsPreserveBothStreams() {
    #expect(
      SimulatorFrameworkBridgeError.failureDetails(
        stderr: Data("stderr".utf8),
        stdout: Data("stdout".utf8)) == "stderr\nstdout")
    #expect(
      SimulatorFrameworkBridgeError.failureDetails(
        stderr: Data(),
        stdout: Data("stdout".utf8)) == "stdout")
    #expect(
      SimulatorFrameworkBridgeError.failureDetails(
        stderr: Data("stderr".utf8),
        stdout: Data()) == "stderr")
    #expect(
      SimulatorFrameworkBridgeError.failureDetails(stderr: Data(), stdout: Data()) == "no output")
  }
}
