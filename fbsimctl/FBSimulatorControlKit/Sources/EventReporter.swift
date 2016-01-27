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

public typealias EventReporterSubject = protocol<FBJSONSerializationDescribeable, FBDebugDescribeable>

public enum EventName : String {
  case Approve = "approve"
  case Boot = "boot"
  case Create = "create"
  case Delete = "delete"
  case Diagnostic = "diagnose"
  case Failure = "failure"
  case Help = "help"
  case Install = "install"
  case Launch = "launch"
  case List = "list"
  case Log = "log"
  case Shutdown = "shutdown"
  case StateChange = "state"
  case Terminate = "terminate"
}

public enum EventType : String {
  case Started = "started"
  case Ended = "ended"
  case Discrete = "discrete"
}

class SimpleEvent : NSObject, EventReporterSubject {
  let eventName: EventName
  let eventType: EventType
  let subject: EventReporterSubject

  init(_ eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    self.eventName = eventName
    self.eventType = eventType
    self.subject = subject
  }

  func jsonSerializableRepresentation() -> AnyObject! {
    return [
      "event_name" : self.eventName.rawValue,
      "event_type" : self.eventType.rawValue,
      "subject" : self.subject.jsonSerializableRepresentation(),
    ]
  }

  var shortDescription: String {
    get {
      return "\(self.eventName) \(self.eventType): \(self.subject)"
    }
  }
}

@objc class LogEvent : NSObject, EventReporterSubject {
  let logString: String
  let level: Int32

  init(_ logString: String, level: Int32) {
    self.logString = logString
    self.level = level
  }

  func jsonSerializableRepresentation() -> AnyObject! {
    return [
      "event_name" : EventName.Log.rawValue,
      "event_type" : EventType.Discrete.rawValue,
      "subject" : self.logString,
      "level" : self.levelString,
      "timestamp" : round(NSDate().timeIntervalSince1970),
    ]
  }

  var shortDescription: String {
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

class SimulatorEvent : NSObject, EventReporterSubject {
  let simulator: FBSimulator
  let eventName: EventName
  let eventType: EventType
  let subject: EventReporterSubject
  let format: Format

  init(simulator: FBSimulator, format: Format, eventName: EventName, eventType: EventType, subject: EventReporterSubject) {
    self.simulator = simulator
    self.format = format
    self.eventName = eventName
    self.eventType = eventType
    self.subject = subject
  }

  func jsonSerializableRepresentation() -> AnyObject! {
    return [
      "simulator" : self.simulatorJSON,
      "event_name" : eventName.rawValue,
      "event_type" : eventType.rawValue,
      "subject" : subject.jsonSerializableRepresentation()
    ]
  }

  var shortDescription: String {
    get {
      return "\(self.formattedSimulator): \(eventName.rawValue) with \(subject.shortDescription)"
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

  private var simulatorJSON: FBJSONSerializationDescribeable {
    get {
      var dictionary: [String : String] = [:]
      for (key, value) in self.simulatorNamePairs {
        dictionary[key] = value
      }
      return dictionary
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

public protocol EventReporter {
  func report(subject: EventReporterSubject)
}

public class EventSinkTranslator : NSObject, FBSimulatorEventSink {
  unowned let simulator: FBSimulator
  let reporter: EventReporter
  let format: Format

  init(simulator: FBSimulator, format: Format, reporter: EventReporter) {
    self.simulator = simulator
    self.reporter = reporter
    self.format = format
    super.init()
    self.simulator.userEventSink = self
  }

  public func containerApplicationDidLaunch(applicationProcess: FBProcessInfo!) {
    self.report(EventName.Launch, applicationProcess)
  }

  public func containerApplicationDidTerminate(applicationProcess: FBProcessInfo!, expected: Bool) {
    self.report(EventName.Terminate, applicationProcess)
  }

  public func simulatorDidLaunch(launchdSimProcess: FBProcessInfo!) {
    self.report(EventName.Launch, launchdSimProcess)
  }

  public func simulatorDidTerminate(launchdSimProcess: FBProcessInfo!, expected: Bool) {
    self.report(EventName.Terminate, launchdSimProcess)
  }

  public func agentDidLaunch(launchConfig: FBAgentLaunchConfiguration!, didStart agentProcess: FBProcessInfo!, stdOut: NSFileHandle!, stdErr: NSFileHandle!) {
    self.report(EventName.Launch, agentProcess)
  }

  public func agentDidTerminate(agentProcess: FBProcessInfo!, expected: Bool) {
    self.report(EventName.Terminate, agentProcess)
  }

  public func applicationDidLaunch(launchConfig: FBApplicationLaunchConfiguration!, didStart applicationProcess: FBProcessInfo!, stdOut: NSFileHandle!, stdErr: NSFileHandle!) {
    self.report(EventName.Launch, applicationProcess)
  }

  public func applicationDidTerminate(applicationProcess: FBProcessInfo!, expected: Bool) {
    self.report(EventName.Terminate, applicationProcess)
  }

  public func logAvailable(log: FBWritableLog!) {
    self.report(EventName.Diagnostic, log)
  }

  public func didChangeState(state: FBSimulatorState) {
    self.report(EventName.StateChange, state.description)
  }

  public func terminationHandleAvailable(terminationHandle: FBTerminationHandleProtocol!) {
    
  }

  public func report(eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    self.reporter.report(SimulatorEvent(
      simulator: self.simulator,
      format: self.format,
      eventName: eventName,
      eventType: eventType,
      subject: subject
    ))
  }

  public func report(eventName: EventName, _ subject: EventReporterSubject) {
    self.report(eventName, EventType.Discrete, subject)
  }
}

public class HumanReadableEventReporter : EventReporter {
  let writer: Writer

  init(writer: Writer) {
    self.writer = writer
  }

  public func report(subject: EventReporterSubject) {
    self.writer.write(subject.shortDescription)
  }
}

@objc public class JSONEventReporter : NSObject, EventReporter {
  let writer: Writer
  let json: JSON

  init(writer: Writer, pretty: Bool) {
    self.writer = writer
    self.json = JSON(pretty: pretty)
  }

  public func report(subject: EventReporterSubject) {
    self.writer.write(try! self.json.serializeToString(subject))
  }
}

public extension Configuration.Options {
  public func createReporter(writer: Writer) -> EventReporter {
    if self.contains(Configuration.Options.JSON) {
      let pretty = self.contains(Configuration.Options.Pretty)
      return JSONEventReporter(writer: writer, pretty: pretty)
    }
    return HumanReadableEventReporter(writer: writer)
  }
}
