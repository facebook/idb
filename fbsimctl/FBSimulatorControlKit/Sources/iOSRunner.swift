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

extension CommandResultRunner {
  static func unimplementedActionRunner(_ action: Action, target: FBiOSTarget, format: FBiOSTargetFormat) -> Runner {
    let (eventName, maybeSubject) = action.reportable
    var actionMessage = eventName.rawValue
    if let subject = maybeSubject {
      actionMessage += " \(subject.description)"
    }
    let message = "Action \(actionMessage) is unimplemented for target \(format.format(target))"
    return CommandResultRunner(result: CommandResult.failure(message))
  }
}

struct iOSActionProvider {
  let context: iOSRunnerContext<(Action, FBiOSTarget, iOSReporter)>

  func makeRunner() -> Runner? {
    let (action, target, reporter) = self.context.value

    switch action {
    case .diagnose(let query, let format):
      return DiagnosticsRunner(reporter, query, query, format)
    case .uninstall(let appBundleID):
      return FutureRunner(reporter, .uninstall, FBEventReporterSubject(string: appBundleID), target.uninstallApplication(withBundleID: appBundleID))
    case .core(let action):
      return iOSTargetRunner.core(reporter, action.eventName, target, action)
    case .coreFuture(let action):
      let future = action.run(with: target, consumer: reporter.reporter.writer, reporter: reporter.reporter)
      return FutureRunner(reporter, action.eventName, action.subject, future)
    case .record(let record):
      switch record {
        case .start(let maybePath):
          return iOSTargetRunner.handled(reporter, nil, RecordSubject(record)) {
            return try target.startRecording(toFile: maybePath)
          }
        case .stop:
          return iOSTargetRunner.simple(reporter, nil, RecordSubject(record)) {
            try target.stopRecording()
          }
      }
    case .search(let search):
      return SearchRunner(target, reporter, search)
    case .stream(let configuration, let output):
      return iOSTargetRunner.handled(reporter, .stream, configuration.subject) {
        let stream = try target.createStream(with: configuration)
        try stream.startStreaming(output.makeWriter())
        return stream
      }
    case .terminate(let bundleID):
      return iOSTargetRunner.simple(reporter, .terminate, FBEventReporterSubject(string: bundleID)) {
        try target.killApplication(withBundleID: bundleID)
      }
    default:
      return nil
    }
  }
}

struct FutureRunner<T : AnyObject> : Runner {
  let reporter: iOSReporter
  let name: EventName?
  let subject: EventReporterSubject
  let future: FBFuture<T>

  init(_ reporter: iOSReporter, _ name: EventName?, _ subject: EventReporterSubject, _ future: FBFuture<T>) {
    self.reporter = reporter
    self.name = name
    self.subject = subject
    self.future = future
  }

  func run() -> CommandResult {
    do {
      if let name = self.name {
        self.reporter.report(name, .started, self.subject)
      }
      _ = try self.future.await()
      if let name = self.name {
        self.reporter.report(name, .ended, self.subject)
      }
      return CommandResult(outcome: .success(nil), handles: [])
    } catch let error as NSError {
      return .failure(error.description)
    } catch let error as JSONError {
      return .failure(error.description)
    } catch {
      return .failure("Unknown Error")
    }
  }
}

struct iOSTargetRunner : Runner {
  let reporter: iOSReporter
  let name: EventName?
  let subject: EventReporterSubject
  let action: () throws -> FBTerminationHandle?

  private init(reporter: iOSReporter, name: EventName?, subject: EventReporterSubject, action: @escaping () throws -> FBTerminationHandle?) {
    self.reporter = reporter
    self.name = name
    self.subject = subject
    self.action = action
  }

  static func simple(_ reporter: iOSReporter, _ name: EventName?, _ subject: EventReporterSubject, _ action: @escaping () throws -> Void) -> iOSTargetRunner {
    return iOSTargetRunner(reporter: reporter, name: name, subject: subject) {
      try action()
      return nil
    }
  }

  static func core(_ reporter: iOSReporter, _ name: EventName?, _ target: FBiOSTarget, _ action: FBiOSTargetAction) -> iOSTargetRunner {
    return iOSTargetRunner(reporter: reporter, name: name, subject: action.subject) {
      return try action.runAction(target: target, reporter: reporter.reporter)
    }
  }

  static func handled(_ reporter: iOSReporter, _ name: EventName?, _ subject: EventReporterSubject, _ action: @escaping () throws -> FBTerminationHandle?) -> iOSTargetRunner {
    return iOSTargetRunner(reporter: reporter, name: name, subject: subject, action: action)
  }

  func run() -> CommandResult {
    do {
      if let name = self.name {
        self.reporter.report(name, .started, self.subject)
      }
      var handles: [FBTerminationHandle] = []
      if let handle = try self.action() {
        handles = [handle]
      }
      if let name = self.name {
        self.reporter.report(name, .ended, self.subject)
      }
      return CommandResult(outcome: .success(nil), handles: handles)
    } catch let error as NSError {
      return .failure(error.description)
    } catch let error as JSONError {
      return .failure(error.description)
    } catch {
      return .failure("Unknown Error")
    }
  }
}

private struct DiagnosticsRunner : Runner {
  let reporter: iOSReporter
  let subject: ControlCoreValue
  let query: FBDiagnosticQuery
  let format: DiagnosticFormat

  init(_ reporter: iOSReporter, _ subject: ControlCoreValue, _ query: FBDiagnosticQuery, _ format: DiagnosticFormat) {
    self.reporter = reporter
    self.subject = subject
    self.query = query
    self.format = format
  }

  func run() -> CommandResult {
    reporter.reportValue(.diagnose, .started, query)
    let diagnostics = self.fetchDiagnostics()
    reporter.reportValue(.diagnose, .ended, query)

    let subjects: [EventReporterSubject] = diagnostics.map { diagnostic in
      return FBEventReporterSubject(
        name: .diagnostic,
        type: .discrete,
        subject: diagnostic.subject
      )
    }
    return .success(FBEventReporterSubject(subjects: subjects))
  }

  func fetchDiagnostics() -> [FBDiagnostic] {
    let diagnostics = self.reporter.target.diagnostics
    let format = self.format

    return diagnostics.perform(query).map { diagnostic in
      switch format {
      case .CurrentFormat:
        return diagnostic
      case .Content:
        return FBDiagnosticBuilder(diagnostic: diagnostic).readIntoMemory().build()
      case .Path:
        return FBDiagnosticBuilder(diagnostic: diagnostic).writeOutToFile().build()
      }
    }
  }
}

private struct SearchRunner : Runner {
  let target: FBiOSTarget
  let reporter: iOSReporter
  let search: FBBatchLogSearch

  init(_ target: FBiOSTarget, _ reporter: iOSReporter, _ search: FBBatchLogSearch) {
    self.target = target
    self.reporter = reporter
    self.search = search
  }

  func run() -> CommandResult {
    do {
      let results = try search.search(on: self.target).await()
      let subject = FBEventReporterSubject(name: .search, type: .discrete, subject: results.subject)
      self.reporter.reporter.report(subject)
      return .success(nil)
    } catch  {
      return .failure("Failed to search with " + self.search.description)
    }
  }
}
