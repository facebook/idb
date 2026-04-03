/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBEventReporterSubject)
public final class FBEventReporterSubject: NSObject {

  @objc public let eventName: String
  @objc public let eventType: FBEventType
  @objc public let arguments: [String]?
  @objc public let duration: NSNumber?
  @objc public let size: NSNumber?
  @objc public let message: String?

  // MARK: Convenience Initializers

  @objc
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

  @objc
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

  @objc
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

  @objc
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
