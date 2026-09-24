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

  private var stagingDirectory: URL {
    directory.appendingPathComponent("staging")
  }

  func testADeliveredNotificationsInvocationLaunchesAStagedCopyOfTheGuest() throws {
    let launched = try deliveredNotificationsInvocation()
      .executablePath(bundledGuestPath: bundledGuestPath, stagingDirectory: stagingDirectory)
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

  func testADeliveredNotificationsInvocationLaunchesWithTheTargetAppsBundleIdentity() throws {
    let launched = try deliveredNotificationsInvocation()
      .executablePath(bundledGuestPath: bundledGuestPath, stagingDirectory: stagingDirectory)
    XCTAssertTrue(FileManager.default.fileExists(atPath: launched))
    let siblingInfoPlist = URL(fileURLWithPath: launched)
      .deletingLastPathComponent()
      .appendingPathComponent("Info.plist")
    let info = try XCTUnwrap(NSDictionary(contentsOf: siblingInfoPlist) as? [String: String])
    XCTAssertEqual(info["CFBundleIdentifier"], "com.apple.news")
    // The lookup is rejected unless this names the executable it sits beside.
    XCTAssertEqual(info["CFBundleExecutable"], URL(fileURLWithPath: launched).lastPathComponent)
  }

  func testAClearDeliveredNotificationsInvocationLaunchesWithTheTargetAppsBundleIdentity() throws {
    let invocation = SimulatorFrameworkBridgeInvocation(
      service: "notifications",
      action: "clear-delivered",
      arguments: ["com.apple.news"])
    let launched =
      try invocation
      .executablePath(bundledGuestPath: bundledGuestPath, stagingDirectory: stagingDirectory)
    let siblingInfoPlist = URL(fileURLWithPath: launched)
      .deletingLastPathComponent()
      .appendingPathComponent("Info.plist")
    let info = try XCTUnwrap(NSDictionary(contentsOf: siblingInfoPlist) as? [String: String])
    XCTAssertEqual(info["CFBundleIdentifier"], "com.apple.news")
    XCTAssertEqual(info["CFBundleExecutable"], URL(fileURLWithPath: launched).lastPathComponent)
  }

  /// The identity is written beside the executable, so two target apps cannot share one.
  func testEachTargetAppLaunchesItsOwnGuest() throws {
    let news = SimulatorFrameworkBridgeInvocation(
      service: "notifications",
      action: "delivered",
      arguments: ["com.apple.news"])
    let weather = SimulatorFrameworkBridgeInvocation(
      service: "notifications",
      action: "delivered",
      arguments: ["com.apple.weather"])
    XCTAssertNotEqual(
      try news.executablePath(bundledGuestPath: bundledGuestPath, stagingDirectory: stagingDirectory),
      try weather.executablePath(bundledGuestPath: bundledGuestPath, stagingDirectory: stagingDirectory))
  }

  func testAnAccessibilityInvocationLaunchesTheBundledGuest() throws {
    let invocation = SimulatorFrameworkBridgeInvocation(
      service: "accessibility",
      action: "describe",
      arguments: ["--pid", "42"])
    XCTAssertEqual(
      try invocation.executablePath(bundledGuestPath: bundledGuestPath, stagingDirectory: stagingDirectory),
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
