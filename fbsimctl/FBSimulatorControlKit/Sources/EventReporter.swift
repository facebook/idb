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
  case Create
  case Boot
  case Shutdown
  case Diagnostic
  case Delete
  case Install
  case Launch
  case Approve
  case StateChange
}

public enum EventType : String {
  case Started = "Started"
  case Ended = "Ended"
  case Discrete = ""
}

public protocol EventReporter : FBSimulatorEventSink {
  func report(eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject)
  func simulatorEvent()
}

public class HumanReadableEventReporter : NSObject, EventReporter {
  unowned let simulator: FBSimulator
  let writer: Writer
  let keywords: [Format.Keywords]

  init(simulator: FBSimulator, writer: Writer, keywords: [Format.Keywords]) {
    self.simulator = simulator
    self.writer = writer
    self.keywords = keywords
    super.init()
    self.simulator.userEventSink = self
  }

  public func containerApplicationDidLaunch(applicationProcess: FBProcessInfo!) {

  }

  public func containerApplicationDidTerminate(applicationProcess: FBProcessInfo!, expected: Bool) {

  }

  public func simulatorDidLaunch(launchdSimProcess: FBProcessInfo!) {

  }

  public func simulatorDidTerminate(launchdSimProcess: FBProcessInfo!, expected: Bool) {

  }

  public func agentDidLaunch(launchConfig: FBAgentLaunchConfiguration!, didStart agentProcess: FBProcessInfo!, stdOut: NSFileHandle!, stdErr: NSFileHandle!) {

  }

  public func agentDidTerminate(agentProcess: FBProcessInfo!, expected: Bool) {

  }

  public func applicationDidLaunch(launchConfig: FBApplicationLaunchConfiguration!, didStart applicationProcess: FBProcessInfo!, stdOut: NSFileHandle!, stdErr: NSFileHandle!) {

  }

  public func applicationDidTerminate(applicationProcess: FBProcessInfo!, expected: Bool) {

  }

  public func diagnosticInformationAvailable(name: String!, process: FBProcessInfo!, value: protocol<NSCoding, NSCopying>!) {

  }

  public func didChangeState(state: FBSimulatorState) {
    self.report(EventName.StateChange, EventType.Discrete, state.description)
  }

  public func terminationHandleAvailable(terminationHandle: FBTerminationHandleProtocol!) {

  }

  public func report(eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    self.writer.write("\(self.formattedSimulator):  \(eventName.rawValue) with \(subject.shortDescription)")
  }

  public func simulatorEvent() {
    self.writer.write(self.formattedSimulator)
  }

  private var formattedSimulator: String {
    get {
      let tokens: [String] = self.keywords.map { keyword in
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
      return tokens.joinWithSeparator(" ")
    }
  }
}

public class JSONEventReporter : NSObject, EventReporter {
  unowned let simulator: FBSimulator
  let writer: Writer
  let json: JSON

  init(simulator: FBSimulator, writer: Writer, pretty: Bool) {
    self.simulator = simulator
    self.writer = writer
    self.json = JSON(pretty: pretty)
    super.init()
    self.simulator.userEventSink = self
  }

  public func containerApplicationDidLaunch(applicationProcess: FBProcessInfo!) {
    self.simulatorEvent()
  }

  public func containerApplicationDidTerminate(applicationProcess: FBProcessInfo!, expected: Bool) {
    self.simulatorEvent()
  }

  public func simulatorDidLaunch(launchdSimProcess: FBProcessInfo!) {
    self.simulatorEvent()
  }

  public func simulatorDidTerminate(launchdSimProcess: FBProcessInfo!, expected: Bool) {
    self.simulatorEvent()
  }

  public func agentDidLaunch(launchConfig: FBAgentLaunchConfiguration!, didStart agentProcess: FBProcessInfo!, stdOut: NSFileHandle!, stdErr: NSFileHandle!) {
    self.simulatorEvent()
  }

  public func agentDidTerminate(agentProcess: FBProcessInfo!, expected: Bool) {
    self.simulatorEvent()
  }

  public func applicationDidLaunch(launchConfig: FBApplicationLaunchConfiguration!, didStart applicationProcess: FBProcessInfo!, stdOut: NSFileHandle!, stdErr: NSFileHandle!) {
    self.simulatorEvent()
  }

  public func applicationDidTerminate(applicationProcess: FBProcessInfo!, expected: Bool) {
    self.simulatorEvent()
  }

  public func diagnosticInformationAvailable(name: String!, process: FBProcessInfo!, value: protocol<NSCoding, NSCopying>!) {
    self.simulatorEvent()
  }

  public func didChangeState(state: FBSimulatorState) {
    self.simulatorEvent()
  }

  public func terminationHandleAvailable(terminationHandle: FBTerminationHandleProtocol!) {
    self.simulatorEvent()
  }

  public func report(eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    do {
      self.writer.write(
        try self.json.serializeToString([
          "simulator" : self.simulator.jsonSerializableRepresentation(),
          "event_name" : eventName.rawValue,
          "event_type" : eventType.rawValue,
          "subject" : subject.jsonSerializableRepresentation()
        ])
      )
    } catch {

    }
  }

  public func simulatorEvent() {
    do {
      self.writer.write(try self.json.serializeToString(self.simulator))
    } catch {
      
    }
  }
}
