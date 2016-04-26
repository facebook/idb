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
  func report(subject: EventReporterSubject)
}

extension EventReporter {
  func reportSimpleBridge(eventName: EventName, _ eventType: EventType, _ subject: ControlCoreValue) {
    self.reportSimple(eventName, eventType, ControlCoreSubject(subject))
  }

  func reportSimple(eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    self.report(SimpleSubject(eventName, eventType, subject))
  }

  func logDebug(string: String) {
    self.report(LogSubject(logString: string, level: Constants.asl_level_debug()))
  }

  func logInfo(string: String) {
    self.report(LogSubject(logString: string, level: Constants.asl_level_info()))
  }
}

public class HumanReadableEventReporter : EventReporter {
  let writer: Writer

  init(writer: Writer) {
    self.writer = writer
  }

  public func report(subject: EventReporterSubject) {
    let description = subject.description
    if description.isEmpty {
      return
    }
    self.writer.write(description)
  }
}

public class JSONEventReporter : NSObject, EventReporter {
  let writer: Writer
  let pretty: Bool

  init(writer: Writer, pretty: Bool) {
    self.writer = writer
    self.pretty = pretty
  }

  public func report(subject: EventReporterSubject) {
    guard let string = try? subject.jsonDescription.serializeToString(pretty) else {
      return
    }
    self.writer.write(string as String)
  }
}

public extension OutputOptions {
  public func createReporter(writer: Writer) -> EventReporter {
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

public extension Command {
  public func createReporter(writer: Writer) -> EventReporter {
    switch self {
    case .Help(let outputOptions, _, _):
      return outputOptions.createReporter(writer)
    case .Perform(let configuration, _, _, _):
      return configuration.outputOptions.createReporter(writer)
    }
  }
}
