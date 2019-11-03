/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation
import XCTestBootstrap

public typealias EventInterpreter = FBEventInterpreterProtocol
public typealias EventReporter = FBEventReporterProtocol

public extension EventReporter {
  var writer: Writer {
    return consumer
  }

  func reportSimpleBridge(_ eventName: EventName, _ eventType: EventType, _ value: ControlCoreValue) {
    reportSimple(eventName, eventType, value.subject)
  }

  func reportSimple(_ eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    report(FBEventReporterSubject(name: eventName, type: eventType, subject: subject))
  }

  func reportError(_ message: String) {
    reportSimpleBridge(.failure, .discrete, FBEventReporterSubject(string: message))
  }

  func logDebug(_ string: String) {
    report(FBEventReporterSubject(logString: string, level: Constants.asl_level_debug))
  }

  func logInfo(_ string: String) {
    report(FBEventReporterSubject(logString: string, level: Constants.asl_level_info))
  }
}

public extension OutputOptions {
  func createReporter(_ writer: Writer) -> EventReporter {
    return FBEventReporter.withInterpreter(createInterpreter(), consumer: writer)
  }

  private func createInterpreter() -> EventInterpreter {
    if contains(OutputOptions.JSON) {
      let pretty = contains(OutputOptions.Pretty)
      return FBEventInterpreter.jsonEventInterpreter(pretty)
    }
    return FBEventInterpreter.humanReadable()
  }

  func createLogWriter() -> Writer {
    return contains(OutputOptions.JSON) ? FBFileWriter.stdOutWriter : FBFileWriter.stdErrWriter
  }
}

public extension Help {
  func createReporter(_ writer: Writer) -> EventReporter {
    return outputOptions.createReporter(writer)
  }
}

public extension Command {
  func createReporter(_ writer: Writer) -> EventReporter {
    return configuration.outputOptions.createReporter(writer)
  }
}

public extension CLI {
  func createReporter(_ writer: Writer) -> EventReporter {
    switch self {
    case let .run(command):
      return command.createReporter(writer)
    case let .show(help):
      return help.createReporter(writer)
    case .print:
      return FBEventReporter.withInterpreter(FBEventInterpreter.humanReadable(), consumer: writer)
    }
  }
}
