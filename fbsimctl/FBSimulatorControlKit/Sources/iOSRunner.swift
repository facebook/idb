/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

struct iOSTargetRunner<A : iOSReporter> : Runner {
  let reporter: A
  let name: EventName?
  let subject: EventReporterSubject
  let action: Void throws -> Void

  init(_ reporter: A, _ name: EventName?, _ subject: EventReporterSubject, _ action: Void throws -> Void) {
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
    }
    return .Success
  }
}

struct UnimplementedRunner : Runner {
  func run() -> CommandResult {
    return CommandResult.Failure("Unimplemented")
  }
}
