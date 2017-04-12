/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

public enum JSONKeys : String {
  case EventName = "event_name"
  case EventType = "event_type"
  case Level = "level"
  case Subject = "subject"
  case Target = "target"
  case Timestamp = "timestamp"
}

public protocol EventReporterSubject : CustomStringConvertible {
  var jsonDescription: JSON { get }
  var subSubjects: [EventReporterSubject] { get }
}

extension EventReporterSubject {
  public var subSubjects: [EventReporterSubject] { get {
    return [self]
  }}
}

extension EventReporterSubject  {
  public func append(_ other: EventReporterSubject) -> EventReporterSubject {
    let joined = self.subSubjects + other.subSubjects
    guard let firstElement = joined.first else {
      return CompositeSubject([])
    }
    if joined.count == 1 {
      return firstElement
    }
    return CompositeSubject(joined)
  }
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
    return JSON.dictionary([
      JSONKeys.EventName.rawValue : JSON.string(self.eventName.rawValue),
      JSONKeys.EventType.rawValue : JSON.string(self.eventType.rawValue),
      JSONKeys.Subject.rawValue : self.subject.jsonDescription,
      JSONKeys.Timestamp.rawValue : JSON.number(NSNumber(value: round(Date().timeIntervalSince1970) as Double)),
    ])
  }}

  var shortDescription: String { get {
    switch self.eventType {
    case .discrete:
      return self.subject.description
    default:
      return "\(self.eventName.rawValue) \(self.eventType.rawValue): \(self.subject.description)"
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
    guard let json = try? JSON.encode(self.value.jsonSerializableRepresentation() as AnyObject) else {
      return JSON.null
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
    let dictionary = self.format.extract(from: self.target)
    return try! JSON.encode(dictionary as AnyObject)
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
  let timestamp: Date

  init(targetSubject: iOSTargetSubject, eventName: EventName, eventType: EventType, subject: EventReporterSubject) {
    self.targetSubject = targetSubject
    self.eventName = eventName
    self.eventType = eventType
    self.subject = subject
    self.timestamp = Date()
  }

  var jsonDescription: JSON { get {
    return JSON.dictionary([
      JSONKeys.EventName.rawValue : JSON.string(self.eventName.rawValue),
      JSONKeys.EventType.rawValue : JSON.string(self.eventType.rawValue),
      JSONKeys.Target.rawValue : self.targetSubject.jsonDescription,
      JSONKeys.Subject.rawValue : self.subject.jsonDescription,
      JSONKeys.Timestamp.rawValue : JSON.number(NSNumber(value: round(self.timestamp.timeIntervalSince1970) as Double)),
    ])
  }}

  var description: String { get {
    switch self.eventType {
    case .discrete:
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
    return JSON.dictionary([
      JSONKeys.EventName.rawValue : JSON.string(EventName.log.rawValue),
      JSONKeys.EventType.rawValue : JSON.string(EventType.discrete.rawValue),
      JSONKeys.Level.rawValue : JSON.string(self.levelString),
      JSONKeys.Subject.rawValue : JSON.string(self.logString),
      JSONKeys.Timestamp.rawValue : JSON.number(NSNumber(value: round(Date().timeIntervalSince1970) as Double)),
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

struct CompositeSubject: EventReporterSubject {
  let array: [EventReporterSubject]

  init (_ array: [EventReporterSubject]) {
    self.array = array
  }

  var subSubjects: [EventReporterSubject] { get {
    return self.array
  }}

  var jsonDescription: JSON { get {
    return JSON.array(self.array.map { $0.jsonDescription } )
  }}

  var description: String { get {
    return "[\(self.array.map({ $0.description }).joined(separator: ", "))]"
  }}
}

struct StringsSubject: EventReporterSubject {
  let strings: [String]

  init (_ strings: [String]) {
    self.strings = strings
  }

  var jsonDescription: JSON { get {
    return JSON.array(self.strings.map { $0.jsonDescription } )
  }}

  var description: String { get {
    return "[\(self.strings.map({ $0.description }).joined(separator: ", "))]"
  }}
}

extension Record : EventReporterSubject {
  public var jsonDescription: JSON {
    var contents: [String : JSON] = [:]
    switch self {
    case .start(let maybePath):
      contents["start"] = JSON.bool(true)
      if let path = maybePath {
        contents["path"] = JSON.string(path)
      } else {
        contents["path"] = JSON.null
      }
    case .stop:
      contents["start"] = JSON.bool(false)
    }
    return JSON.dictionary(contents)
  }

  public var description: String { get {
    switch self {
    case .start(let maybePath):
      let destination = maybePath ?? "Default Destination"
      return "Start Recording \(destination)"
    case .stop:
      return "Stop Recording"
    }
  }}
}

extension String : EventReporterSubject {
  public var jsonDescription: JSON { get {
    return JSON.string(self)
  }}

  public var description: String { get {
    return self
  }}
}

extension Bool : EventReporterSubject {
  public var jsonDescription: JSON { get {
    return JSON.number(NSNumber(value: self as Bool))
  }}
}
