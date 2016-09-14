/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

public protocol EventReporterSubject : CustomStringConvertible {
  var jsonDescription: JSON { get }
}

struct SimpleSubject : EventReporterSubject {
  let eventName: EventName
  let eventType: EventType
  let subject: EventReporterSubject

  init(_ eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    self.eventName = eventName
    self.eventType = eventType
    self.subject = subject
  }

  var jsonDescription: JSON { get {
    return JSON.JDictionary([
      "event_name" : JSON.JString(self.eventName.rawValue),
      "event_type" : JSON.JString(self.eventType.rawValue),
      "subject" : self.subject.jsonDescription,
      "timestamp" : JSON.JNumber(NSNumber(double: round(NSDate().timeIntervalSince1970))),
    ])
  }}

  var shortDescription: String { get {
    switch self.eventType {
    case .Discrete:
      return self.subject.description
    default:
      return "\(self.eventName) \(self.eventType): \(self.subject.description)"
    }
  }}

  var description: String { get {
      return self.shortDescription
  }}
}

struct ControlCoreSubject : EventReporterSubject {
  let value: ControlCoreValue

  init(_ value: ControlCoreValue) {
    self.value = value
  }

  var jsonDescription: JSON { get {
    guard let json = try? JSON.encode(self.value.jsonSerializableRepresentation()) else {
      return JSON.JNull
    }
    return json
  }}

  var description: String { get {
    return self.value.description
  }}
}

struct iOSTargetSubject: EventReporterSubject {
  let target: FBiOSTarget
  let format: FBiOSTargetFormat

  var jsonDescription: JSON { get {
    let dictionary = self.format.extractFrom(self.target)
    return try! JSON.encode(dictionary)
  }}

  var description: String { get {
    return self.format.format(self.target)
  }}
}

struct iOSTargetWithSubject : EventReporterSubject {
  let targetSubject: iOSTargetSubject
  let eventName: EventName
  let eventType: EventType
  let subject: EventReporterSubject
  let timestamp: NSDate

  init(targetSubject: iOSTargetSubject, eventName: EventName, eventType: EventType, subject: EventReporterSubject) {
    self.targetSubject = targetSubject
    self.eventName = eventName
    self.eventType = eventType
    self.subject = subject
    self.timestamp = NSDate()
  }

  var jsonDescription: JSON { get {
    return JSON.JDictionary([
      "event_name" : JSON.JString(self.eventName.rawValue),
      "event_type" : JSON.JString(self.eventType.rawValue),
      "target" : self.targetSubject.jsonDescription,
      "subject" : self.subject.jsonDescription,
      "timestamp" : JSON.JNumber(NSNumber(double: round(self.timestamp.timeIntervalSince1970))),
    ])
  }}

  var description: String { get {
    switch self.eventType {
    case .Discrete:
      return "\(self.targetSubject): \(self.eventName.rawValue): \(self.subject.description)"
    default:
      return ""
    }
  }}
}

struct LogSubject : EventReporterSubject {
  let logString: String
  let level: Int32

  var jsonDescription: JSON { get {
    return JSON.JDictionary([
      "event_name" : JSON.JString(EventName.Log.rawValue),
      "event_type" : JSON.JString(EventType.Discrete.rawValue),
      "level" : JSON.JString(self.levelString),
      "subject" : JSON.JString(self.logString),
      "timestamp" : JSON.JNumber(NSNumber(double: round(NSDate().timeIntervalSince1970))),
    ])
  }}

  var description: String { get {
    return self.logString
  }}

  var levelString: String { get {
    switch self.level {
    case Constants.asl_level_debug(): return "debug"
    case Constants.asl_level_err(): return "error"
    case Constants.asl_level_info(): return "info"
    default: return "unknown"
    }
  }}
}

struct ArraySubject<A where A : EventReporterSubject> : EventReporterSubject {
  let array: [A]

  init (_ array: [A]) {
    self.array = array
  }

  var jsonDescription: JSON { get {
    return JSON.JArray(self.array.map { $0.jsonDescription } )
  }}

  var description: String { get {
    return "[\(array.map({ $0.description }).joinWithSeparator(", "))]"
  }}
}

extension String : EventReporterSubject {
  public var jsonDescription: JSON { get {
    return JSON.JString(self)
  }}

  public var description: String { get {
    return self
  }}
}

extension Bool : EventReporterSubject {
  public var jsonDescription: JSON { get {
    return JSON.JNumber(NSNumber(bool: self))
  }}
}
