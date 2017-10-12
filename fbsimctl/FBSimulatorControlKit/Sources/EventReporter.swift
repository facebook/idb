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
import XCTestBootstrap

public typealias EventInterpreter = FBEventInterpreterProtocol
public typealias EventReporter = FBEventReporterProtocol

public  extension EventReporter {
  public var writer: Writer { get {
    return self.consumer
  }}

  func reportSimpleBridge(_ eventName: EventName, _ eventType: EventType, _ value: ControlCoreValue) {
    self.reportSimple(eventName, eventType, value.subject)
  }

  func reportSimple(_ eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    self.report(FBEventReporterSubject(name: eventName, type: eventType, subject: subject))
  }

  func reportError(_ message: String) {
    self.reportSimpleBridge(.failure, .discrete, FBEventReporterSubject(string: message))
  }

  func logDebug(_ string: String) {
    self.report(FBEventReporterSubject(logString: string, level: Constants.asl_level_debug))
  }

  func logInfo(_ string: String) {
    self.report(FBEventReporterSubject(logString: string, level: Constants.asl_level_info))
  }
}

public extension OutputOptions {
  public func createReporter(_ writer: Writer) -> EventReporter {
    return FBEventReporter.withInterpreter(self.createInterpreter(), consumer: writer)
  }

  private func createInterpreter() -> EventInterpreter {
    if self.contains(OutputOptions.JSON) {
      let pretty = self.contains(OutputOptions.Pretty)
      return FBEventInterpreter.jsonEventInterpreter(pretty)
    }
    return FBEventInterpreter.humanReadable()
  }

  public func createLogWriter() -> Writer {
    return self.contains(OutputOptions.JSON) ? FileHandleWriter.stdOutWriter : FileHandleWriter.stdErrWriter
  }
}

public extension Help {
  public func createReporter(_ writer: Writer) -> EventReporter {
    return self.outputOptions.createReporter(writer)
  }
}

public extension Command {
  public func createReporter(_ writer: Writer) -> EventReporter {
    return self.configuration.outputOptions.createReporter(writer)
  }
}

public extension CLI {
  public func createReporter(_ writer: Writer) -> EventReporter {
    switch self {
    case .run(let command):
      return command.createReporter(writer)
    case .show(let help):
      return help.createReporter(writer)
    case .print:
      return FBEventReporter.withInterpreter(FBEventInterpreter.humanReadable(), consumer: writer)
    }
  }
}
