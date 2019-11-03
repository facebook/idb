/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public typealias EventReporterSubject = FBEventReporterSubjectProtocol

extension EventReporterSubject {
  var jsonDescription: JSON {
    return try! JSON.encode(jsonSerializableRepresentation as AnyObject)
  }

  public func append(_ other: EventReporterSubject) -> EventReporterSubject {
    let joined = subSubjects + other.subSubjects
    guard let firstElement = joined.first else {
      return FBEventReporterSubject(subjects: [])
    }
    if joined.count == 1 {
      return firstElement
    }
    return FBEventReporterSubject(subjects: joined)
  }
}

extension FBJSONSerializable {
  var subject: FBEventReporterSubject {
    return FBEventReporterSubject(value: self)
  }
}

@objc class RecordSubject: NSObject, EventReporterSubject {
  var eventName: FBEventName?
  var eventType: FBEventType?
  var argument: [String: String]?
  var arguments: [String]?
  var duration: NSNumber?
  var message: String?
  var size: NSNumber?

  let record: Record

  init(_ record: Record) {
    self.record = record
  }

  var jsonSerializableRepresentation: Any {
    var contents: [String: NSObject] = [:]
    switch self.record {
    case let .start(maybePath):
      contents["start"] = NSNumber(value: true)
      if let path = maybePath {
        contents["path"] = path as NSString
      } else {
        contents["path"] = NSNull()
      }
    case .stop:
      contents["start"] = NSNumber(value: false)
    }
    return contents
  }

  override var description: String {
    switch record {
    case let .start(maybePath):
      let destination = maybePath ?? "Default Destination"
      return "Start Recording \(destination)"
    case .stop:
      return "Stop Recording"
    }
  }

  var subSubjects: [FBEventReporterSubjectProtocol] {
    return [self]
  }
}

@objc class ListenSubject: NSObject, EventReporterSubject {
  var eventName: FBEventName?
  var eventType: FBEventType?
  var argument: [String: String]?
  var arguments: [String]?
  var duration: NSNumber?
  var message: String?
  var size: NSNumber?

  let interface: ListenInterface

  init(_ interface: ListenInterface) {
    self.interface = interface
  }

  var jsonSerializableRepresentation: Any {
    var json: [String: Any] = [
      "stdin": NSNumber(value: self.interface.stdin),
      "handle": self.interface.continuation?.futureType.rawValue ?? NSNull(),
    ]
    if let http = self.interface.http {
      json["http"] = NSNumber(value: http)
    } else {
      json["http"] = NSNull()
    }
    if let hid = self.interface.hid {
      json["hid"] = hid
    } else {
      json["hid"] = NSNull()
    }
    return json
  }

  public override var description: String {
    if let listenDescription = self.listenDescription {
      return listenDescription
    }
    var description = "Http: "
    if let httpPort = self.interface.http {
      description += httpPort.description
    } else {
      description += "No"
    }
    description += " Hid: "
    if let hidPort = self.interface.hid {
      description += hidPort.description
    } else {
      description += "No"
    }
    description += " stdin: \(interface.stdin)"
    if let continuation = self.interface.continuation {
      description += " due to \(continuation.futureType.rawValue)"
    }
    return description
  }

  private var listenDescription: String? {
    if !interface.isEmptyListen {
      return nil
    }
    guard let continuation = self.interface.continuation else {
      return nil
    }
    return continuation.futureType.listenDescription
  }

  var subSubjects: [FBEventReporterSubjectProtocol] {
    return [self]
  }
}
