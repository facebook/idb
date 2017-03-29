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

public protocol EventReporter {
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

open class HumanReadableEventReporter : EventReporter {
  let writer: Writer

  init(writer: Writer) {
    self.writer = writer
  }

  open func report(_ subject: EventReporterSubject) {
    for item in subject.subSubjects {
      let string = item.description
      if string.isEmpty {
        return
      }
      self.writer.write(string)
    }
  }
}

open class JSONEventReporter : NSObject, EventReporter {
  let writer: Writer
  let pretty: Bool

  init(writer: Writer, pretty: Bool) {
    self.writer = writer
    self.pretty = pretty
  }

  open func report(_ subject: EventReporterSubject) {
    for item in subject.subSubjects {
      let json = item.jsonDescription
      guard let _ = try? json.getValue(JSONKeys.EventName.rawValue).getString() else {
        assertionFailure("\(json) does not have a \(JSONKeys.EventName.rawValue)")
        return
      }
      guard let _ = try? json.getValue(JSONKeys.EventType.rawValue).getString() else {
        assertionFailure("\(json) does not have a \(JSONKeys.EventType.rawValue)")
        return
      }
      do {
        let line = try json.serializeToString(pretty)
        self.writer.write(line as String)
      } catch let error {
        assertionFailure("Failed to Serialize \(json) to string: \(error)")
      }
    }
  }
}

public extension OutputOptions {
  public func createReporter(_ writer: Writer) -> EventReporter {
    if self.contains(OutputOptions.JSON) {
      let pretty = self.contains(OutputOptions.Pretty)
      return JSONEventReporter(writer: writer, pretty: pretty)
    }
    return HumanReadableEventReporter(writer: writer)
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
    }
  }
}
