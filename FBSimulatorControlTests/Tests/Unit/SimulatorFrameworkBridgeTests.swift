/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
@_implementationOnly import SimulatorFrameworkBridgeProtocol
import XCTest

final class SimulatorFrameworkBridgeTests: XCTestCase {

  private var directory: URL!
  private var bundledGuestPath: String!

  /// A stand-in for the guest shipped in the companion's `Resources`.
  ///
  /// The contents do not matter — nothing here runs it. What matters is that it is a real file
  /// in a directory this test owns, so an assertion about what sits beside it is an assertion
  /// about what the resolver put there.
  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let guestURL = directory.appendingPathComponent("SimulatorFrameworkBridge-iOS")
    try Data("guest".utf8).write(to: guestURL)
    bundledGuestPath = guestURL.path
  }

  override func tearDownWithError() throws {
    if let directory {
      try? FileManager.default.removeItem(at: directory)
    }
    directory = nil
    bundledGuestPath = nil
    try super.tearDownWithError()
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

  func testAStagedGuestIsACopyOfTheBundledGuest() throws {
    let launched = try staged("com.apple.news")
    XCTAssertNotEqual(launched, bundledGuestPath)
    XCTAssertEqual(
      URL(fileURLWithPath: launched).lastPathComponent,
      URL(fileURLWithPath: bundledGuestPath).lastPathComponent)
    XCTAssertEqual(
      FileManager.default.contents(atPath: launched),
      FileManager.default.contents(atPath: bundledGuestPath))
    // `proc_pidpath` resolves a symlink back to the bundled guest, whose directory names no app.
    let type = try FileManager.default.attributesOfItem(atPath: launched)[.type] as? FileAttributeType
    XCTAssertEqual(type, .typeRegular)
  }

  func testAStagedGuestLaunchesWithTheTargetAppsBundleIdentity() throws {
    let launched = try staged("com.apple.news")
    let siblingInfoPlist = URL(fileURLWithPath: launched)
      .deletingLastPathComponent()
      .appendingPathComponent("Info.plist")
    let info = try XCTUnwrap(NSDictionary(contentsOf: siblingInfoPlist) as? [String: String])
    XCTAssertEqual(info["CFBundleIdentifier"], "com.apple.news")
    // The lookup is rejected unless this names the executable it sits beside.
    XCTAssertEqual(info["CFBundleExecutable"], URL(fileURLWithPath: launched).lastPathComponent)
  }

  /// The identity is written beside the executable, so two target apps cannot share one.
  func testEachTargetAppLaunchesItsOwnGuest() throws {
    XCTAssertNotEqual(try staged("com.apple.news"), try staged("com.apple.weather"))
  }

  func testOnlyABundleIdentifierCanBeStagedAsAnIdentity() {
    XCTAssertEqual(SimulatorFrameworkBridgeStaging.bundleIdentity("com.apple.news"), "com.apple.news")
    for bundleID in ["", ".", "..", "../news", "com/apple"] {
      XCTAssertNil(SimulatorFrameworkBridgeStaging.bundleIdentity(bundleID), bundleID)
    }
  }

  func testDeliveredNotificationCommandsAreStaged() {
    XCTAssertEqual(BridgeCommand.notifications(.delivered(bundleID: "com.apple.news")).route, .staged(bundleIdentity: "com.apple.news"))
    XCTAssertEqual(BridgeCommand.notifications(.clearDelivered(bundleID: "com.apple.news")).route, .staged(bundleIdentity: "com.apple.news"))
  }

  func testCommandsWithoutAnIdentityUseThePersistentGuest() {
    for command: BridgeCommand in [.notifications(.list(bundleID: "com.apple.news")), .notifications(.delivered(bundleID: "../news")), .clearPhotos, .accessibility([:])] {
      XCTAssertEqual(command.route, .persistent, "\(command)")
    }
  }

  func testFailureDetailsPreserveBothStreams() {
    XCTAssertEqual(
      SimulatorFrameworkBridgeError.failureDetails(
        stderr: Data("stderr".utf8),
        stdout: Data("stdout".utf8)),
      "stderr\nstdout")
    XCTAssertEqual(
      SimulatorFrameworkBridgeError.failureDetails(
        stderr: Data(),
        stdout: Data("stdout".utf8)),
      "stdout")
    XCTAssertEqual(
      SimulatorFrameworkBridgeError.failureDetails(
        stderr: Data("stderr".utf8),
        stdout: Data()),
      "stderr")
    XCTAssertEqual(
      SimulatorFrameworkBridgeError.failureDetails(stderr: Data(), stdout: Data()),
      "no output")
  }
}
