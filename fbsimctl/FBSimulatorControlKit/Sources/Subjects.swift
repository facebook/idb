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
  var subSubjects: [EventReporterSubject] { get }
}

extension FBEventReporterSubject : EventReporterSubject {
  public var jsonDescription: JSON { get {
    return try! JSON.encode(self.jsonSerializableRepresentation as AnyObject)
  }}
}

extension EventReporterSubject {
  public var subSubjects: [EventReporterSubject] { get {
    return [self]
  }}
}

/**
 FBControlCore Classes must interact with NSObject subclasses, this bridges Swift -> Objective-C
 */
@objc class EventReporterSubjectBridge : NSObject, FBEventReporterSubjectProtocol {
  let wrapped: EventReporterSubject

  init(_ wrapped: EventReporterSubject) {
    self.wrapped = wrapped
  }

  var subSubjects: [FBEventReporterSubjectProtocol] { get {
    return self.wrapped.subSubjects.map(EventReporterSubjectBridge.init)
  }}

  override var description: String { get {
    return self.wrapped.description
  }}

  var jsonSerializableRepresentation: Any { get {
    return self.wrapped.jsonDescription.decode()
  }}
}

extension FBJSONSerializable {
  var subject: FBEventReporterSubject { get {
    return FBEventReporterSubject(value: self)
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
      JSONKeys.eventName.rawValue : JSON.string(self.eventName.rawValue),
      JSONKeys.eventType.rawValue : JSON.string(self.eventType.rawValue),
      JSONKeys.subject.rawValue : self.subject.jsonDescription,
      JSONKeys.timestamp.rawValue : JSON.number(NSNumber(value: round(Date().timeIntervalSince1970) as Double)),
    ])
  }}

  var shortDescription: String { get {
    switch self.eventType {
    case EventType.discrete:
      return self.subject.description
    default:
      return "\(self.eventName.rawValue) \(self.eventType.rawValue): \(self.subject.description)"
    }
  }}

  var description: String { get {
    return self.shortDescription
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
