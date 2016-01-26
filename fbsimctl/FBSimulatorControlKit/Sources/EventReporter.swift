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
  case List = "list"
  case Create = "create"
  case Boot = "boot"
  case Shutdown = "shutdown"
  case Diagnostic = "diagnose"
  case Delete = "delete"
  case Install = "install"
  case Launch = "launch"
  case Terminate = "terminate"
  case Approve = "approve"
  case StateChange = "state"
}

public enum EventType : String {
  case Started = "started"
  case Ended = "ended"
  case Discrete = "discrete"
}

class SimulatorEvent : NSObject, EventReporterSubject {
  let simulator: FBSimulator
  let eventName: EventName
  let eventType: EventType
  let subject: EventReporterSubject
  let keywords: [Format.Keywords]

  init(simulator: FBSimulator, keywords: [Format.Keywords], eventName: EventName, eventType: EventType, subject: EventReporterSubject) {
    self.simulator = simulator
    self.keywords = keywords
    self.eventName = eventName
    self.eventType = eventType
    self.subject = subject
  }

  func jsonSerializableRepresentation() -> AnyObject! {
    return [
      "simulator" : self.simulator.jsonSerializableRepresentation(),
      "event_name" : eventName.rawValue,
      "event_type" : eventType.rawValue,
      "subject" : subject.jsonSerializableRepresentation()
    ]
  }

  var shortDescription: String {
    get {
      return "\(self.formattedSimulator):  \(eventName.rawValue) with \(subject.shortDescription)"
    }
  }

  private var formattedSimulator: String {
    get {
      let tokens: [String] = self.keywords
        .map { keyword in
          switch keyword {
          case .UDID:
            return simulator.udid
          case .Name:
            return simulator.name
          case .DeviceName:
            guard let configuration = simulator.configuration else {
              return "unknown-name"
            }
            return configuration.deviceName
          case .OSVersion:
            guard let configuration = simulator.configuration else {
              return "unknown-os"
            }
            return configuration.osVersionString
          case .State:
            return simulator.stateString
          case .ProcessIdentifier:
            guard let process = simulator.launchdSimProcess else {
              return "no-process"
            }
            return process.processIdentifier.description
          }
      }
      return tokens
        .map { token in
          if token.rangeOfCharacterFromSet(NSCharacterSet.whitespaceCharacterSet(), options: NSStringCompareOptions(), range: nil) == nil {
            return token
          }
          return "'\(token)'"
        }
        .joinWithSeparator(" ")
    }
  }
}

public protocol EventReporter {
  func report(subject: EventReporterSubject)
}

public class EventSinkTranslator : NSObject, FBSimulatorEventSink {
  unowned let simulator: FBSimulator
  let reporter: EventReporter
  let keywords: [Format.Keywords]

  init(simulator: FBSimulator, reporter: EventReporter, keywords: [Format.Keywords]) {
    self.simulator = simulator
    self.reporter = reporter
    self.keywords = keywords
    super.init()
    self.simulator.userEventSink = self
  }

  public static func create(writer: Writer, format: Format, simulator: FBSimulator) -> EventSinkTranslator {
    switch format {
    case .HumanReadable(let keywords):
      return EventSinkTranslator(simulator: simulator, reporter: HumanReadableEventReporter(writer: writer), keywords: keywords)
    case .JSON(let pretty):
      return EventSinkTranslator(simulator: simulator, reporter: JSONEventReporter(writer: writer, pretty: pretty), keywords: [])
    }
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
      keywords: self.keywords,
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

public class JSONEventReporter : EventReporter {
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
