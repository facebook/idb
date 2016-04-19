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

public class SimulatorReporter : NSObject, FBSimulatorEventSink {
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
    self.reportValue(EventName.Launch, EventType.Discrete, applicationProcess)
  }

  public func containerApplicationDidTerminate(applicationProcess: FBProcessInfo!, expected: Bool) {
    self.reportValue(EventName.Terminate, EventType.Discrete, applicationProcess)
  }

  public func bridgeDidConnect(bridge: FBSimulatorBridge!) {
    self.reportValue(EventName.Launch, EventType.Discrete, bridge)
  }

  public func bridgeDidDisconnect(bridge: FBSimulatorBridge!, expected: Bool) {
    self.reportValue(EventName.Terminate, EventType.Discrete, bridge)
  }

  public func testmanagerDidConnect(testManager: FBTestManager!) {

  }

  public func testmanagerDidDisconnect(testManager: FBTestManager!) {

  }

  public func simulatorDidLaunch(launchdSimProcess: FBProcessInfo!) {
    self.reportValue(EventName.Launch, EventType.Discrete, launchdSimProcess)
  }

  public func simulatorDidTerminate(launchdSimProcess: FBProcessInfo!, expected: Bool) {
    self.reportValue(EventName.Terminate, EventType.Discrete, launchdSimProcess)
  }

  public func agentDidLaunch(launchConfig: FBAgentLaunchConfiguration!, didStart agentProcess: FBProcessInfo!, stdOut: NSFileHandle!, stdErr: NSFileHandle!) {
    self.reportValue(EventName.Launch, EventType.Discrete, agentProcess)
  }

  public func agentDidTerminate(agentProcess: FBProcessInfo!, expected: Bool) {
    self.reportValue(EventName.Terminate, EventType.Discrete, agentProcess)
  }

  public func applicationDidLaunch(launchConfig: FBApplicationLaunchConfiguration!, didStart applicationProcess: FBProcessInfo!) {
    self.reportValue(EventName.Launch, EventType.Discrete, applicationProcess)
  }

  public func applicationDidTerminate(applicationProcess: FBProcessInfo!, expected: Bool) {
    self.reportValue(EventName.Terminate, EventType.Discrete, applicationProcess)
  }

  public func diagnosticAvailable(log: FBDiagnostic!) {
    self.reportValue(EventName.Diagnostic, EventType.Discrete, log)
  }

  public func didChangeState(state: FBSimulatorState) {
    self.reportValue(EventName.StateChange, EventType.Discrete, state.description as NSString)
  }

  public func terminationHandleAvailable(terminationHandle: FBTerminationHandleProtocol!) {

  }
}

extension SimulatorReporter {
  public func report(eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    let simulatorSubject = SimulatorSubject(simulator: self.simulator, format: self.format)
    self.reporter.report(SimulatorWithSubject(
      simulatorSubject: simulatorSubject,
      eventName: eventName,
      eventType: eventType,
      subject: subject
    ))
  }

  public func reportValue(eventName: EventName, _ eventType: EventType, _ value: ControlCoreValue) {
    self.report(eventName, eventType, ControlCoreSubject(value))
  }

}
