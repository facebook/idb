/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation

open class SimulatorReporter: NSObject, FBSimulatorEventSink, iOSReporter {
  public unowned let simulator: FBSimulator
  public let reporter: EventReporter
  public let format: FBiOSTargetFormat

  init(simulator: FBSimulator, format: FBiOSTargetFormat, reporter: EventReporter) {
    self.simulator = simulator
    self.reporter = reporter
    self.format = format
    super.init()
    simulator.userEventSink = self
  }

  open var target: FBiOSTarget {
    return self.simulator
  }

  open func containerApplicationDidLaunch(_ applicationProcess: FBProcessInfo) {
    reportValue(.launch, .discrete, applicationProcess)
  }

  open func containerApplicationDidTerminate(_ applicationProcess: FBProcessInfo, expected _: Bool) {
    reportValue(.terminate, .discrete, applicationProcess)
  }

  open func connectionDidConnect(_ connection: FBSimulatorConnection) {
    reportValue(.launch, .discrete, connection)
  }

  open func connectionDidDisconnect(_ connection: FBSimulatorConnection, expected _: Bool) {
    reportValue(.terminate, .discrete, connection)
  }

  open func testmanagerDidConnect(_: FBTestManager) {}

  open func testmanagerDidDisconnect(_: FBTestManager) {}

  open func simulatorDidLaunch(_ launchdProcess: FBProcessInfo) {
    reportValue(.launch, .discrete, launchdProcess)
  }

  open func simulatorDidTerminate(_ launchdProcess: FBProcessInfo, expected _: Bool) {
    reportValue(.terminate, .discrete, launchdProcess)
  }

  open func agentDidLaunch(_ operation: FBSimulatorAgentOperation) {
    reportValue(.launch, .discrete, operation)
  }

  open func agentDidTerminate(_ operation: FBSimulatorAgentOperation, statLoc _: Int32) {
    reportValue(.terminate, .discrete, operation)
  }

  public func applicationDidLaunch(_ operation: FBSimulatorApplicationOperation) {
    reportValue(.launch, .discrete, operation)
    if operation.configuration.waitForDebugger {
      reporter.logInfo("Application launched. To debug, run lldb -p \(operation.processIdentifier).")
    }
  }

  open func applicationDidTerminate(_ operation: FBSimulatorApplicationOperation, expected _: Bool) {
    reportValue(.terminate, .discrete, operation)
  }

  open func didChange(_ state: FBiOSTargetState) {
    reportValue(.stateChange, .discrete, FBEventReporterSubject(string: state.description))
  }
}
