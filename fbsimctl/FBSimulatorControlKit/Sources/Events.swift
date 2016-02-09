/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBSimulatorControl

public typealias EventReporterSubject = protocol<JSONDescribeable, CustomStringConvertible>
public typealias SimulatorControlSubject = protocol<FBJSONSerializationDescribeable, CustomStringConvertible>

public enum EventName : String {
  case Approve = "approve"
  case Boot = "boot"
  case Create = "create"
  case Delete = "delete"
  case Diagnose = "diagnose"
  case Failure = "failure"
  case Help = "help"
  case Install = "install"
  case Launch = "launch"
  case Relaunch = "relaunch"
  case List = "list"
  case Diagnostic = "diagnostic"
  case Shutdown = "shutdown"
  case StateChange = "state"
  case Terminate = "terminate"
}

public enum EventType : String {
  case Started = "started"
  case Ended = "ended"
  case Discrete = "discrete"
}

extension NSString : FBJSONSerializationDescribeable {
  public func jsonSerializableRepresentation() -> AnyObject! {
    return self
  }
}

extension NSArray : FBJSONSerializationDescribeable {
  public func jsonSerializableRepresentation() -> AnyObject! {
    return self
  }
}

extension NSDictionary : FBJSONSerializationDescribeable {
  public func jsonSerializableRepresentation() -> AnyObject! {
    return self
  }
}

@objc class SimulatorControlSubjectBridge : NSObject, JSONDescribeable {
  let subject: SimulatorControlSubject

  init(_ subject: SimulatorControlSubject) {
    self.subject = subject
  }

  var jsonDescription: JSON {
    get {
      return try! JSON.encode(self.subject.jsonSerializableRepresentation())
    }
  }

  override var description: String {
    get {
      return self.subject.description
    }
  }
}

class SimpleEvent : NSObject, JSONDescribeable {
  let eventName: EventName
  let eventType: EventType
  let subject: EventReporterSubject

  init(_ eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    self.eventName = eventName
    self.eventType = eventType
    self.subject = subject
  }

  var jsonDescription: JSON {
    get {
      return JSON.Dictionary([
        "event_name" : JSON.String(self.eventName.rawValue),
        "event_type" : JSON.String(self.eventType.rawValue),
        "subject" : self.subject.jsonDescription,
        "timestamp" : JSON.Number(NSNumber(double: round(NSDate().timeIntervalSince1970))),
      ])
    }
  }

  var shortDescription: String {
    get {
      return "\(self.eventName) \(self.eventType): \(self.subject)"
    }
  }
}

@objc class LogEvent : NSObject, JSONDescribeable {
  let logString: String
  let level: Int32

  init(_ logString: String, level: Int32) {
    self.logString = logString
    self.level = level
  }

  var jsonDescription: JSON {
    get {
      return JSON.Dictionary([
        "event_name" : JSON.String(EventName.Diagnostic.rawValue),
        "event_type" : JSON.String(EventType.Discrete.rawValue),
        "subject" : JSON.String(self.logString),
        "level" : JSON.String(self.levelString),
        "timestamp" : JSON.Number(NSNumber(double: round(NSDate().timeIntervalSince1970))),
      ])
    }
  }

  override var description: String {
    get {
      return self.logString
    }
  }

  var levelString: String {
    get {
      switch self.level {
      case Constants.asl_level_debug(): return "debug"
      case Constants.asl_level_err(): return "error"
      case Constants.asl_level_info(): return "info"
      default: return "unknown"
      }
    }
  }
}

class SimulatorEvent : NSObject, JSONDescribeable {
  let simulator: FBSimulator
  let eventName: EventName
  let eventType: EventType
  let subject: SimulatorControlSubject
  let format: Format

  init(simulator: FBSimulator, format: Format, eventName: EventName, eventType: EventType, subject: SimulatorControlSubject) {
    self.simulator = simulator
    self.format = format
    self.eventName = eventName
    self.eventType = eventType
    self.subject = subject
  }

  var jsonDescription: JSON {
    get {
      return JSON.Dictionary([
        "simulator" : SimulatorControlSubjectBridge(self.simulator).jsonDescription,
        "event_name" : JSON.String(self.eventName.rawValue),
        "event_type" : JSON.String(self.eventType.rawValue),
        "subject" : SimulatorControlSubjectBridge(self.subject).jsonDescription,
        "timestamp" : JSON.Number(NSNumber(double: round(NSDate().timeIntervalSince1970))),
      ])
    }
  }

  override var description: String {
    get {
      return "\(self.formattedSimulator): \(eventName.rawValue) with \(subject.description)"
    }
  }

  private var formattedSimulator: String {
    get {
      return self.simulatorNamePairs
        .map { (_, token) in
          if token.rangeOfCharacterFromSet(NSCharacterSet.whitespaceCharacterSet(), options: NSStringCompareOptions(), range: nil) == nil {
            return token
          }
          return "'\(token)'"
        }
        .joinWithSeparator(" ")
    }
  }

  private var simulatorJSON: JSON {
    get {
      var dictionary: [NSString : JSON] = [:]
      for (key, value) in self.simulatorNamePairs {
        dictionary[key] = JSON.String(value)
      }
      return JSON.Dictionary(dictionary)
    }
  }

  private var simulatorNamePairs: [(String, String)] {
    get {
      let simulator = self.simulator
      return self.format
        .map { keyword in
          switch keyword {
          case .UDID:
            return ("udid", simulator.udid)
          case .Name:
            return ("name", simulator.name)
          case .DeviceName:
            return ("device", simulator.configuration?.deviceName ?? "unknown-name")
          case .OSVersion:
            return ("os", simulator.configuration?.osVersionString ?? "unknown-os")
          case .State:
            return ("state", simulator.stateString)
          case .ProcessIdentifier:
            return ("pid", simulator.launchdSimProcess?.description ?? "no-process")
          }
      }
    }
  }
}
