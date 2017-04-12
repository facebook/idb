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

public protocol EventInterpreter {
  func interpret(_ subject: EventReporterSubject) -> [String]
}

public protocol EventReporter {
  var interpreter: EventInterpreter { get }
  func report(_ subject: EventReporterSubject)
}

extension EventReporter {
  func reportSimpleBridge(_ eventName: EventName, _ eventType: EventType, _ subject: ControlCoreValue) {
    self.reportSimple(eventName, eventType, ControlCoreSubject(subject))
  }

  func reportSimple(_ eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    self.report(SimpleSubject(eventName, eventType, subject))
  }

  func reportError(_ message: String) {
    self.reportSimpleBridge(.failure, .discrete, message as NSString)
  }

  func logDebug(_ string: String) {
    self.report(LogSubject(logString: string, level: Constants.asl_level_debug()))
  }

  func logInfo(_ string: String) {
    self.report(LogSubject(logString: string, level: Constants.asl_level_info()))
  }
}

class WritingEventReporter : EventReporter {
  public let writer: Writer
  public let interpreter: EventInterpreter

  init(writer: Writer, interpreter: EventInterpreter) {
    self.writer = writer
    self.interpreter = interpreter
  }

  public func report(_ subject: EventReporterSubject) {
    for line in self.interpreter.interpret(subject) {
      self.writer.write(line)
    }
  }
}

struct HumanReadableEventInterpreter : EventInterpreter {
  public func interpret(_ subject: EventReporterSubject) -> [String] {
    return subject.subSubjects.flatMap { item in
      let string = item.description
      if string.isEmpty {
        return nil
      }
      return string
    }
  }
}

struct JSONEventInterpreter : EventInterpreter {
  let pretty: Bool

  public func interpret(_ subject: EventReporterSubject) -> [String] {
    return subject.subSubjects.flatMap { item in
      let json = item.jsonDescription
      guard let _ = try? json.getValue(JSONKeys.EventName.rawValue).getString() else {
        assertionFailure("\(json) does not have a \(JSONKeys.EventName.rawValue)")
        return nil
      }
      guard let _ = try? json.getValue(JSONKeys.EventType.rawValue).getString() else {
        assertionFailure("\(json) does not have a \(JSONKeys.EventType.rawValue)")
        return nil
      }
      do {
        return try json.serializeToString(pretty)
      } catch let error {
        assertionFailure("Failed to Serialize \(json) to string: \(error)")
        return nil
      }
    }
  }
}

public extension OutputOptions {
  public func createReporter(_ writer: Writer) -> EventReporter {
    return WritingEventReporter(writer: writer, interpreter: self.createInterpreter())
  }

  private func createInterpreter() -> EventInterpreter {
    if self.contains(OutputOptions.JSON) {
      let pretty = self.contains(OutputOptions.Pretty)
      return JSONEventInterpreter(pretty: pretty)
    }
    return HumanReadableEventInterpreter()
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
      return WritingEventReporter(writer: writer, interpreter: HumanReadableEventInterpreter())
    }
  }
}
