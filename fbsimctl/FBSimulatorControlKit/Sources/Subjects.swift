/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

struct SimpleSubject : JSONDescribeable, CustomStringConvertible {
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
      return JSON.JDictionary([
        "event_name" : JSON.JString(self.eventName.rawValue),
        "event_type" : JSON.JString(self.eventType.rawValue),
        "subject" : self.subject.jsonDescription,
        "timestamp" : JSON.JNumber(NSNumber(double: round(NSDate().timeIntervalSince1970))),
      ])
    }
  }

  var shortDescription: String {
    get {
      switch self.eventType {
      case .Discrete:
        return self.subject.description
      default:
        return "\(self.eventName) \(self.eventType): \(self.subject.description)"
      }
    }
  }

  var description: String {
    get {
      return self.shortDescription
    }
  }
}

struct ControlCoreSubject : JSONDescribeable, CustomStringConvertible {
  let value: ControlCoreValue

  init(_ value: ControlCoreValue) {
    self.value = value
  }

  var jsonDescription: JSON {
    get {
      guard let json = try? JSON.encode(self.value.jsonSerializableRepresentation()) else {
        return JSON.JNull
      }
      return json
    }
  }

  var description: String {
    get {
      return self.value.description
    }
  }
}

struct SimulatorSubject: JSONDescribeable, CustomStringConvertible {
  let simulator: FBSimulator
  let format: Format

  var jsonDescription: JSON {
    get {
      return self.simulatorJSON
    }
  }

  var description: String {
    get {
      return self.formattedSimulator
    }
  }

  private var formattedSimulator: String {
    get {
      return self.simulatorValuePairs
        .map { (_, token) in
          guard let token = token else {
            return ""
          }
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
      var dictionary: [String : JSON] = [:]
      for (key, maybeValue) in self.simulatorValuePairs {
        guard let value = maybeValue else {
          dictionary[key] = JSON.JNull
          continue
        }
        dictionary[key] = JSON.JString(value)
      }
      return JSON.JDictionary(dictionary)
    }
  }

  private var simulatorValuePairs: [(String, String?)] {
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
            return ("device", simulator.configuration?.deviceName)
          case .OSVersion:
            return ("os", simulator.configuration?.osVersionString)
          case .State:
            return ("state", simulator.stateString)
          case .ProcessIdentifier:
            return ("pid", simulator.launchdSimProcess?.processIdentifier.description)
          }
      }
    }
  }
}

struct SimulatorWithSubject : JSONDescribeable, CustomStringConvertible {
  let simulatorSubject: SimulatorSubject
  let eventName: EventName
  let eventType: EventType
  let subject: EventReporterSubject
  let timestamp: NSDate

  init(simulatorSubject: SimulatorSubject, eventName: EventName, eventType: EventType, subject: EventReporterSubject) {
    self.simulatorSubject = simulatorSubject
    self.eventName = eventName
    self.eventType = eventType
    self.subject = subject
    self.timestamp = NSDate()
  }

  var jsonDescription: JSON {
    get {
      return JSON.JDictionary([
        "event_name" : JSON.JString(self.eventName.rawValue),
        "event_type" : JSON.JString(self.eventType.rawValue),
        "simulator" : self.simulatorSubject.jsonDescription,
        "subject" : self.subject.jsonDescription,
        "timestamp" : JSON.JNumber(NSNumber(double: round(self.timestamp.timeIntervalSince1970))),
      ])
    }
  }

  var description: String {
    get {
      switch self.eventType {
      case .Discrete:
        return "\(self.simulatorSubject): \(self.eventName.rawValue): \(self.subject.description)"
      default:
        return ""
      }
    }
  }
}

struct LogSubject : JSONDescribeable, CustomStringConvertible {
  let logString: String
  let level: Int32

  var jsonDescription: JSON {
    get {
      return JSON.JDictionary([
        "event_name" : JSON.JString(EventName.Log.rawValue),
        "event_type" : JSON.JString(EventType.Discrete.rawValue),
        "level" : JSON.JString(self.levelString),
        "subject" : JSON.JString(self.logString),
        "timestamp" : JSON.JNumber(NSNumber(double: round(NSDate().timeIntervalSince1970))),
      ])
    }
  }

  var description: String {
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

struct ArraySubject<A where A : JSONDescribeable, A : CustomStringConvertible> : JSONDescribeable, CustomStringConvertible {
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
