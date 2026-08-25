/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public struct FBEventType: RawRepresentable, Equatable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }

  public static let started = FBEventType(rawValue: "started")
  public static let ended = FBEventType(rawValue: "ended")
  public static let discrete = FBEventType(rawValue: "discrete")
  public static let success = FBEventType(rawValue: "success")
  public static let failure = FBEventType(rawValue: "failure")
}

public struct FBEventReporterSubject: Sendable {

  public let eventName: String
  public let eventType: FBEventType
  public let arguments: [String]?
  public let duration: NSNumber?
  public let size: NSNumber?
  public let message: String?
  /// Additional per-event string columns attached to this subject alone —
  /// unlike reporter metadata, which applies to every subsequent event.
  public let normals: [String: String]
  /// Additional per-event integer columns attached to this subject alone.
  public let ints: [String: Int]

  // MARK: Convenience Initializers

  public init(forEvent eventName: String) {
    self.init(
      eventName: eventName,
      eventType: .discrete,
      arguments: nil,
      duration: nil,
      size: nil,
      message: nil,
      normals: [:],
      ints: [:]
    )
  }

  public init(forStartedCall call: String, arguments: [String]) {
    self.init(
      eventName: call,
      eventType: .started,
      arguments: arguments,
      duration: nil,
      size: nil,
      message: nil,
      normals: [:],
      ints: [:]
    )
  }

  public init(
    forSuccessfulCall call: String,
    duration: TimeInterval,
    size: NSNumber?,
    arguments: [String],
    normals: [String: String] = [:],
    ints: [String: Int] = [:]
  ) {
    self.init(
      eventName: call,
      eventType: .success,
      arguments: arguments,
      duration: FBEventReporterSubject.durationMilliseconds(duration),
      size: size,
      message: nil,
      normals: normals,
      ints: ints
    )
  }

  public init(
    forFailingCall call: String,
    duration: TimeInterval,
    message: String,
    size: NSNumber?,
    arguments: [String],
    normals: [String: String] = [:],
    ints: [String: Int] = [:]
  ) {
    self.init(
      eventName: call,
      eventType: .failure,
      arguments: arguments,
      duration: FBEventReporterSubject.durationMilliseconds(duration),
      size: size,
      message: message,
      normals: normals,
      ints: ints
    )
  }

  // MARK: Private

  // Saturating on purpose: durations can arrive negative (wall clocks step
  // backwards under NTP between a call's start and end) or non-finite, and
  // UInt.init traps on both, killing the process for a telemetry value.
  private static func durationMilliseconds(_ timeInterval: TimeInterval) -> NSNumber {
    let milliseconds = timeInterval * 1000
    guard milliseconds.isFinite, milliseconds > 0 else {
      return NSNumber(value: UInt(0))
    }
    guard milliseconds < Double(UInt.max) else {
      return NSNumber(value: UInt.max)
    }
    return NSNumber(value: UInt(milliseconds))
  }

  private init(eventName: String, eventType: FBEventType, arguments: [String]?, duration: NSNumber?, size: NSNumber?, message: String?, normals: [String: String], ints: [String: Int]) {
    self.eventName = eventName
    self.eventType = eventType
    self.arguments = arguments
    self.duration = duration
    self.size = size
    self.message = message
    self.normals = normals
    self.ints = ints
  }
}
