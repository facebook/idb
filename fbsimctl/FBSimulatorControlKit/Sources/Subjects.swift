/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

public typealias EventReporterSubject = FBEventReporterSubjectProtocol

extension EventReporterSubject {
  var jsonDescription: JSON { get {
    return try! JSON.encode(self.jsonSerializableRepresentation as AnyObject)
  }}

  public func append(_ other: EventReporterSubject) -> EventReporterSubject {
    let joined = self.subSubjects + other.subSubjects
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
  var subject: FBEventReporterSubject { get {
    return FBEventReporterSubject(value: self)
  }}
}

@objc class RecordSubject : NSObject, EventReporterSubject {
  let record: Record

  init(_ record: Record) {
    self.record = record
  }

  var jsonSerializableRepresentation: Any { get {
    var contents: [String : NSObject] = [:]
    switch self.record {
    case .start(let maybePath):
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
    }}

  override var description: String { get {
    switch self.record {
    case .start(let maybePath):
      let destination = maybePath ?? "Default Destination"
      return "Start Recording \(destination)"
    case .stop:
      return "Stop Recording"
    }
  }}

  var subSubjects: [FBEventReporterSubjectProtocol] { get {
    return [self]
  }}
}

@objc class ListenSubject : NSObject, EventReporterSubject {
  let interface: ListenInterface

  init(_ interface: ListenInterface) {
    self.interface = interface
  }

  var jsonSerializableRepresentation: Any { get {
    var json: [String : Any] = [
      "stdin" : NSNumber(value: self.interface.stdin),
      "handle" : self.interface.handle?.handleType.rawValue ?? NSNull(),
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
  }}

  override public var description: String { get {
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
    description += " stdin: \(self.interface.stdin)"
    if let handle = self.interface.handle {
      description += " due to \(handle.handleType.rawValue)"
    }
    return description
  }}

  private var listenDescription: String? { get {
    if !self.interface.isEmptyListen {
      return nil
    }
    guard  let handle = self.interface.handle else {
      return nil
    }
    return handle.handleType.listenDescription
  }}

  var subSubjects: [FBEventReporterSubjectProtocol] { get {
    return [self]
  }}
}

