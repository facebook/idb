/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
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

  private func deliveredNotificationsInvocation() -> SimulatorFrameworkBridgeInvocation {
    SimulatorFrameworkBridgeInvocation(
      service: "notifications",
      action: "delivered",
      arguments: ["com.apple.news"])
  }

  func testTheGuestParsesTheServiceThenTheActionThenTheRest() {
    XCTAssertEqual(
      deliveredNotificationsInvocation().guestArguments,
      ["notifications", "delivered", "com.apple.news"])
  }

  func testADeliveredNotificationsInvocationLaunchesTheBundledGuest() {
    XCTAssertEqual(
      deliveredNotificationsInvocation().executablePath(bundledGuestPath: bundledGuestPath),
      bundledGuestPath)
  }

  /// BUG: the guest launches from a directory with no `Info.plist`, so `BSBundleIDForPID` answers
  /// nil for it and `usernotificationsd` refuses every cross-bundle request — flipped in the
  /// following commit.
  func testADeliveredNotificationsInvocationLaunchesWithNoBundleIdentity() {
    let launched = deliveredNotificationsInvocation()
      .executablePath(bundledGuestPath: bundledGuestPath)
    XCTAssertTrue(FileManager.default.fileExists(atPath: launched))
    let siblingInfoPlist = URL(fileURLWithPath: launched)
      .deletingLastPathComponent()
      .appendingPathComponent("Info.plist")
    XCTAssertFalse(FileManager.default.fileExists(atPath: siblingInfoPlist.path))
  }

  /// The guest shipped in `Resources` is shared by every invocation, so an identity established
  /// by writing beside it would be one identity for all of them.
  func testTheBundledGuestIsSharedBetweenTargetApps() {
    let news = SimulatorFrameworkBridgeInvocation(
      service: "notifications",
      action: "delivered",
      arguments: ["com.apple.news"])
    let weather = SimulatorFrameworkBridgeInvocation(
      service: "notifications",
      action: "delivered",
      arguments: ["com.apple.weather"])
    XCTAssertEqual(
      news.executablePath(bundledGuestPath: bundledGuestPath),
      weather.executablePath(bundledGuestPath: bundledGuestPath))
  }

  func testAnAccessibilityInvocationLaunchesTheBundledGuest() {
    let invocation = SimulatorFrameworkBridgeInvocation(
      service: "accessibility",
      action: "describe",
      arguments: ["--pid", "42"])
    XCTAssertEqual(
      invocation.executablePath(bundledGuestPath: bundledGuestPath),
      bundledGuestPath)
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
