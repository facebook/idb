/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
import Foundation
import Testing

@Suite
struct EventReporterSubjectTests {

  @Test
  func successfulCallDurationConvertsSecondsToMilliseconds() {
    let subject = EventReporterSubject(forSuccessfulCall: "list_apps", duration: 1.5, size: nil, arguments: [])
    #expect(subject.duration == NSNumber(value: UInt(1500)))
  }

  @Test
  func failingCallDurationConvertsSecondsToMilliseconds() {
    let subject = EventReporterSubject(forFailingCall: "list_apps", duration: 0.25, message: "failed", size: nil, arguments: [])
    #expect(subject.duration == NSNumber(value: UInt(250)))
  }

  @Test
  func zeroDurationIsZeroMilliseconds() {
    let subject = EventReporterSubject(forSuccessfulCall: "list_apps", duration: 0, size: nil, arguments: [])
    #expect(subject.duration == NSNumber(value: UInt(0)))
  }

  @Test
  func negativeDurationSaturatesToZero() {
    let subject = EventReporterSubject(forSuccessfulCall: "list_apps", duration: -5, size: nil, arguments: [])
    #expect(subject.duration == NSNumber(value: UInt(0)))
  }

  @Test
  func naNDurationSaturatesToZero() {
    let subject = EventReporterSubject(forSuccessfulCall: "list_apps", duration: .nan, size: nil, arguments: [])
    #expect(subject.duration == NSNumber(value: UInt(0)))
  }

  @Test
  func infiniteDurationSaturatesToZero() {
    let subject = EventReporterSubject(forSuccessfulCall: "list_apps", duration: .infinity, size: nil, arguments: [])
    #expect(subject.duration == NSNumber(value: UInt(0)))
  }

  @Test
  func overflowingDurationSaturatesToUIntMax() {
    let subject = EventReporterSubject(forSuccessfulCall: "list_apps", duration: 1e30, size: nil, arguments: [])
    #expect(subject.duration == NSNumber(value: UInt.max))
  }
}
