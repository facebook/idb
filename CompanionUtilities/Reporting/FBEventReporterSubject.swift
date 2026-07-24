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

public final class FBEventReporterSubject: NSObject {

  public let eventName: String
  public let eventType: FBEventType
  public let arguments: [String]?
  public let duration: NSNumber?
  public let size: NSNumber?
  public let message: String?

  // MARK: Convenience Initializers

  public convenience init(forEvent eventName: String) {
    self.init(
      eventName: eventName,
      eventType: .discrete,
      arguments: nil,
      duration: nil,
      size: nil,
      message: nil
    )
  }

  public convenience init(forStartedCall call: String, arguments: [String]) {
    self.init(
      eventName: call,
      eventType: .started,
      arguments: arguments,
      duration: nil,
      size: nil,
      message: nil
    )
  }

  public convenience init(forSuccessfulCall call: String, duration: TimeInterval, size: NSNumber?, arguments: [String]) {
    self.init(
      eventName: call,
      eventType: .success,
      arguments: arguments,
      duration: FBEventReporterSubject.durationMilliseconds(duration),
      size: size,
      message: nil
    )
  }

  public convenience init(forFailingCall call: String, duration: TimeInterval, message: String, size: NSNumber?, arguments: [String]) {
    self.init(
      eventName: call,
      eventType: .failure,
      arguments: arguments,
      duration: FBEventReporterSubject.durationMilliseconds(duration),
      size: size,
      message: message
    )
  }

  // MARK: Factory Methods (ObjC compatibility)
  //
  // Swift callers use the convenience initializers above; these selector-named
  // factories exist only for Objective-C, so they compile only where ObjC interop
  // is available.
  #if canImport(ObjectiveC)
  @objc(subjectForEvent:)
  public class func subject(forEvent eventName: String) -> FBEventReporterSubject {
    return FBEventReporterSubject(forEvent: eventName)
  }

  @objc(subjectForStartedCall:arguments:)
  public class func subject(forStartedCall call: String, arguments: [String]) -> FBEventReporterSubject {
    return FBEventReporterSubject(forStartedCall: call, arguments: arguments)
  }

  @objc(subjectForSuccessfulCall:duration:size:arguments:)
  public class func subject(forSuccessfulCall call: String, duration: TimeInterval, size: NSNumber?, arguments: [String]) -> FBEventReporterSubject {
    return FBEventReporterSubject(forSuccessfulCall: call, duration: duration, size: size, arguments: arguments)
  }

  @objc(subjectForFailingCall:duration:message:size:arguments:)
  public class func subject(forFailingCall call: String, duration: TimeInterval, message: String, size: NSNumber?, arguments: [String]) -> FBEventReporterSubject {
    return FBEventReporterSubject(forFailingCall: call, duration: duration, message: message, size: size, arguments: arguments)
  }
  #endif

  // MARK: Private

  private class func durationMilliseconds(_ timeInterval: TimeInterval) -> NSNumber {
    let milliseconds = UInt(timeInterval * 1000)
    return NSNumber(value: milliseconds)
  }

  private init(eventName: String, eventType: FBEventType, arguments: [String]?, duration: NSNumber?, size: NSNumber?, message: String?) {
    self.eventName = eventName
    self.eventType = eventType
    self.arguments = arguments
    self.duration = duration
    self.size = size
    self.message = message
    super.init()
  }
}
