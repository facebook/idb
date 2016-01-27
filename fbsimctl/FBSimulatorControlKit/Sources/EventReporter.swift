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

public typealias EventReporterSubject = protocol<JSONDescribeable, FBDebugDescribeable>
public typealias SimulatorControlSubject = protocol<FBJSONSerializationDescribeable, FBDebugDescribeable>

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

extension NSString : FBJSONSerializationDescribeable {
  public func jsonSerializableRepresentation() -> AnyObject! {
    return self
  }
}

extension NSString : FBDebugDescribeable {
  override public var debugDescription: String {
    get {
      return self.description
    }
  }

  public var shortDescription: String {
    get {
      return self.description
    }
  }
}

extension NSArray : FBJSONSerializationDescribeable {
  public func jsonSerializableRepresentation() -> AnyObject! {
    return self
  }
}
extension NSArray : FBDebugDescribeable {
  override public var debugDescription: String {
    get {
      return self.description
    }
  }

  public var shortDescription: String {
    get {
      return self.description
    }
  }
}

extension NSDictionary : FBJSONSerializationDescribeable {
  public func jsonSerializableRepresentation() -> AnyObject! {
    return self
  }
}

@objc private class SimulatorControlSubjectBridge : NSObject, JSONDescribeable, FBDebugDescribeable {
  let subject: SimulatorControlSubject

  init(_ subject: SimulatorControlSubject) {
    self.subject = subject
  }

  var jsonDescription: JSON {
    get {
      return try! JSON.encode(self.subject.jsonSerializableRepresentation())
    }
  }

  @objc var shortDescription: String! {
    get {
      return self.subject.shortDescription
    }
  }
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

  var jsonDescription: JSON {
    get {
      return JSON.Dictionary([
        "event_name" : JSON.String(self.eventName.rawValue),
        "event_type" : JSON.String(self.eventType.rawValue),
        "subject" : self.subject.jsonDescription,
      ])
    }
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

  var jsonDescription: JSON {
    get {
      return JSON.Dictionary([
        "event_name" : JSON.String(EventName.Log.rawValue),
        "event_type" : JSON.String(EventType.Discrete.rawValue),
        "subject" : JSON.String(self.logString),
        "level" : JSON.String(self.levelString),
        "timestamp" : JSON.Number(NSNumber(double: round(NSDate().timeIntervalSince1970))),
      ])
    }
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
        "subject" : SimulatorControlSubjectBridge(self.subject).jsonDescription
      ])
    }
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

public protocol EventReporter {
  func report(subject: EventReporterSubject)
}

extension EventReporter {
  func reportSimple(eventName: EventName, _ eventType: EventType, _ subject: SimulatorControlSubject) {
    self.report(SimpleEvent(eventName, eventType, SimulatorControlSubjectBridge(subject)))
  }
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
    self.reportSimulator(EventName.Launch, applicationProcess)
  }

  public func containerApplicationDidTerminate(applicationProcess: FBProcessInfo!, expected: Bool) {
    self.reportSimulator(EventName.Terminate, applicationProcess)
  }

  public func simulatorDidLaunch(launchdSimProcess: FBProcessInfo!) {
    self.reportSimulator(EventName.Launch, launchdSimProcess)
  }

  public func simulatorDidTerminate(launchdSimProcess: FBProcessInfo!, expected: Bool) {
    self.reportSimulator(EventName.Terminate, launchdSimProcess)
  }

  public func agentDidLaunch(launchConfig: FBAgentLaunchConfiguration!, didStart agentProcess: FBProcessInfo!, stdOut: NSFileHandle!, stdErr: NSFileHandle!) {
    self.reportSimulator(EventName.Launch, agentProcess)
  }

  public func agentDidTerminate(agentProcess: FBProcessInfo!, expected: Bool) {
    self.reportSimulator(EventName.Terminate, agentProcess)
  }

  public func applicationDidLaunch(launchConfig: FBApplicationLaunchConfiguration!, didStart applicationProcess: FBProcessInfo!, stdOut: NSFileHandle!, stdErr: NSFileHandle!) {
    self.reportSimulator(EventName.Launch, applicationProcess)
  }

  public func applicationDidTerminate(applicationProcess: FBProcessInfo!, expected: Bool) {
    self.reportSimulator(EventName.Terminate, applicationProcess)
  }

  public func logAvailable(log: FBWritableLog!) {
    self.reportSimulator(EventName.Diagnostic, log)
  }

  public func didChangeState(state: FBSimulatorState) {
    self.reportSimulator(EventName.StateChange, state.description)
  }

  public func terminationHandleAvailable(terminationHandle: FBTerminationHandleProtocol!) {
    
  }
}

extension EventSinkTranslator {
  public func reportSimulator(eventName: EventName, _ eventType: EventType, _ subject: SimulatorControlSubject) {
    self.reporter.report(SimulatorEvent(
      simulator: self.simulator,
      format: self.format,
      eventName: eventName,
      eventType: eventType,
      subject: subject
    ))
  }

  public func reportSimulator(eventName: EventName, _ subject: SimulatorControlSubject) {
    self.reportSimulator(eventName, EventType.Discrete, subject)
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
  let pretty: Bool

  init(writer: Writer, pretty: Bool) {
    self.writer = writer
    self.pretty = pretty
  }

  public func report(subject: EventReporterSubject) {
    self.writer.write(try! subject.jsonDescription.serializeToString(pretty) as String)
  }

  func reportLogBridge(subject: LogEvent) {
    self.report(subject)
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
