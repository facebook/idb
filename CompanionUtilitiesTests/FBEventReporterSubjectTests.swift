/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
// Uses XCTest to match the existing tests in this target; migrating the whole
// target to Swift Testing is a separate effort.
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

final class FBEventReporterSubjectTests: XCTestCase {

  func testSuccessfulCallDurationConvertsSecondsToMilliseconds() {
    let subject = FBEventReporterSubject(forSuccessfulCall: "list_apps", duration: 1.5, size: nil, arguments: [])
    XCTAssertEqual(subject.duration, NSNumber(value: UInt(1500)))
  }

  func testFailingCallDurationConvertsSecondsToMilliseconds() {
    let subject = FBEventReporterSubject(forFailingCall: "list_apps", duration: 0.25, message: "failed", size: nil, arguments: [])
    XCTAssertEqual(subject.duration, NSNumber(value: UInt(250)))
  }

  func testZeroDurationIsZeroMilliseconds() {
    let subject = FBEventReporterSubject(forSuccessfulCall: "list_apps", duration: 0, size: nil, arguments: [])
    XCTAssertEqual(subject.duration, NSNumber(value: UInt(0)))
  }

  func testSubMillisecondNegativeDurationTruncatesToZero() {
    let subject = FBEventReporterSubject(forSuccessfulCall: "list_apps", duration: -0.0005, size: nil, arguments: [])
    XCTAssertEqual(subject.duration, NSNumber(value: UInt(0)))
  }

  func testNegativeDurationSaturatesToZero() {
    let subject = FBEventReporterSubject(forSuccessfulCall: "list_apps", duration: -5, size: nil, arguments: [])
    XCTAssertEqual(subject.duration, NSNumber(value: UInt(0)))
  }

  func testNegativeMillisecondDurationSaturatesToZero() {
    let subject = FBEventReporterSubject(forFailingCall: "list_apps", duration: -0.001, message: "failed", size: nil, arguments: [])
    XCTAssertEqual(subject.duration, NSNumber(value: UInt(0)))
  }

  func testNaNDurationSaturatesToZero() {
    let subject = FBEventReporterSubject(forSuccessfulCall: "list_apps", duration: .nan, size: nil, arguments: [])
    XCTAssertEqual(subject.duration, NSNumber(value: UInt(0)))
  }

  func testInfiniteDurationSaturatesToZero() {
    let subject = FBEventReporterSubject(forSuccessfulCall: "list_apps", duration: .infinity, size: nil, arguments: [])
    XCTAssertEqual(subject.duration, NSNumber(value: UInt(0)))
  }

  func testNegativeInfiniteDurationSaturatesToZero() {
    let subject = FBEventReporterSubject(forSuccessfulCall: "list_apps", duration: -.infinity, size: nil, arguments: [])
    XCTAssertEqual(subject.duration, NSNumber(value: UInt(0)))
  }

  func testOverflowingDurationSaturatesToUIntMax() {
    let subject = FBEventReporterSubject(forSuccessfulCall: "list_apps", duration: 1e30, size: nil, arguments: [])
    XCTAssertEqual(subject.duration, NSNumber(value: UInt.max))
  }
}
