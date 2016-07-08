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
import FBDeviceControl

struct iOSActionProvider {
  let context: iOSRunnerContext<(Action, FBiOSTarget, iOSReporter)>

  func makeRunner() -> Runner? {
    let (action, target, reporter) = self.context.value

    switch action {
    case .List:
      let format = self.context.format
      return iOSTargetRunner(reporter, nil, ControlCoreSubject(target as! ControlCoreValue)) {
        let subject = iOSTargetSubject(target: target, format: format)
        reporter.reporter.reportSimple(EventName.List, EventType.Discrete, subject)
      }
    case .Install(let appPath):
      return iOSTargetRunner(reporter, EventName.Install, ControlCoreSubject(appPath as NSString)) {
        try target.installApplicationWithPath(appPath)
      }
    default:
      return nil
    }
  }
}

struct iOSTargetRunner : Runner {
  let reporter: iOSReporter
  let name: EventName?
  let subject: EventReporterSubject
  let action: Void throws -> Void

  init(_ reporter: iOSReporter, _ name: EventName?, _ subject: EventReporterSubject, _ action: Void throws -> Void) {
    self.reporter = reporter
    self.name = name
    self.subject = subject
    self.action = action
  }

  func run() -> CommandResult {
    do {
      if let name = self.name {
        self.reporter.report(name, EventType.Started, self.subject)
      }
      try self.action()
      if let name = self.name {
        self.reporter.report(name, EventType.Ended, self.subject)
      }
    } catch let error as NSError {
      return .Failure(error.description)
    } catch let error as JSONError {
      return .Failure(error.description)
    } catch {
      return .Failure("Unknown Error")
    }
    return .Success
  }
}
