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

open class SimulatorReporter : NSObject, FBSimulatorEventSink, iOSReporter {
  unowned open let simulator: FBSimulator
  open let reporter: EventReporter
  open let format: FBiOSTargetFormat

  init(simulator: FBSimulator, format: FBiOSTargetFormat, reporter: EventReporter) {
    self.simulator = simulator
    self.reporter = reporter
    self.format = format
    super.init()
    simulator.userEventSink = self
  }

  open var target: FBiOSTarget { get {
    return self.simulator
  }}

  open func containerApplicationDidLaunch(_ applicationProcess: FBProcessInfo) {
    self.reportValue(EventName.Launch, EventType.Discrete, applicationProcess)
  }

  open func containerApplicationDidTerminate(_ applicationProcess: FBProcessInfo, expected: Bool) {
    self.reportValue(EventName.Terminate, EventType.Discrete, applicationProcess)
  }

  open func connectionDidConnect(_ connection: FBSimulatorConnection) {
    self.reportValue(EventName.Launch, EventType.Discrete, connection)
  }

  open func connectionDidDisconnect(_ connection: FBSimulatorConnection, expected: Bool) {
    self.reportValue(EventName.Terminate, EventType.Discrete, connection)
  }

  open func testmanagerDidConnect(_ testManager: FBTestManager) {

  }

  open func testmanagerDidDisconnect(_ testManager: FBTestManager) {

  }

  open func simulatorDidLaunch(_ launchdProcess: FBProcessInfo) {
    self.reportValue(EventName.Launch, EventType.Discrete, launchdProcess)
  }

  open func simulatorDidTerminate(_ launchdProcess: FBProcessInfo, expected: Bool) {
    self.reportValue(EventName.Terminate, EventType.Discrete, launchdProcess)
  }

  open func agentDidLaunch(_ launchConfig: FBAgentLaunchConfiguration, didStart agentProcess: FBProcessInfo, stdOut: FileHandle, stdErr: FileHandle) {
    self.reportValue(EventName.Launch, EventType.Discrete, agentProcess)
  }

  open func agentDidTerminate(_ agentProcess: FBProcessInfo, expected: Bool) {
    self.reportValue(EventName.Terminate, EventType.Discrete, agentProcess)
  }

  open func applicationDidLaunch(_ launchConfig: FBApplicationLaunchConfiguration, didStart applicationProcess: FBProcessInfo) {
    self.reportValue(EventName.Launch, EventType.Discrete, applicationProcess)
  }

  open func applicationDidTerminate(_ applicationProcess: FBProcessInfo, expected: Bool) {
    self.reportValue(EventName.Terminate, EventType.Discrete, applicationProcess)
  }

  open func diagnosticAvailable(_ log: FBDiagnostic) {
    self.reportValue(EventName.Diagnostic, EventType.Discrete, log)
  }

  open func didChange(_ state: FBSimulatorState) {
    self.reportValue(EventName.StateChange, EventType.Discrete, state.description as NSString)
  }

  open func terminationHandleAvailable(_ terminationHandle: FBTerminationHandle) {

  }
}
