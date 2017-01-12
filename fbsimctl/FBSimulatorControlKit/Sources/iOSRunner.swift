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
    case .install(let appPath):
      return iOSTargetRunner(
        reporter: reporter,
        name: EventName.Install,
        subject: ControlCoreSubject(appPath as NSString),
        interaction: FBCommandInteractions.installApplication(withPath: appPath, command: target)
      )
    case .uninstall(let appBundleID):
      return iOSTargetRunner(reporter, EventName.Uninstall,ControlCoreSubject(appBundleID as NSString)) {
        try target.uninstallApplication(withBundleID: appBundleID)
      }
    case .launchApp(let appLaunch):
      return iOSTargetRunner(
        reporter: reporter,
        name: EventName.Launch,
        subject: ControlCoreSubject(appLaunch),
        interaction: FBCommandInteractions.launchApplication(appLaunch, command: target)
      )
    case .listApps:
      return iOSTargetRunner(reporter, nil, ControlCoreSubject(target as! ControlCoreValue)) {
        let subject = ControlCoreSubject(target.installedApplications().map { $0.jsonSerializableRepresentation() }  as NSArray)
        reporter.reporter.reportSimple(EventName.ListApps, EventType.Discrete, subject)
      }
    case .record(let start):
      return iOSTargetRunner(
        reporter: reporter,
        name: EventName.Record,
        subject: start,
        interaction: start ? FBCommandInteractions.startRecording(withCommand: target) : FBCommandInteractions.stopRecording(withCommand: target)
      )
    case .terminate(let bundleID):
      return iOSTargetRunner(
        reporter: reporter,
        name: EventName.Terminate,
        subject: ControlCoreSubject(bundleID as NSString),
        interaction: FBCommandInteractions.killApplication(withBundleID: bundleID, command: target)
      )
    default:
      return nil
    }
  }
}

struct iOSTargetRunner : Runner {
  let reporter: iOSReporter
  let name: EventName?
  let subject: EventReporterSubject
  let interaction: FBInteractionProtocol

  init(reporter: iOSReporter, name: EventName?, subject: EventReporterSubject, interaction: FBInteractionProtocol) {
    self.reporter = reporter
    self.name = name
    self.subject = subject
    self.interaction = interaction
  }

  init(_ reporter: iOSReporter, _ name: EventName?, _ subject: EventReporterSubject, _ action: @escaping (Void) throws -> Void) {
    self.init(reporter: reporter, name: name, subject: subject, interaction: Interaction(action))
  }

  func run() -> CommandResult {
    do {
      if let name = self.name {
        self.reporter.report(name, EventType.Started, self.subject)
      }
      try self.interaction.perform()
      if let name = self.name {
        self.reporter.report(name, EventType.Ended, self.subject)
      }
    } catch let error as NSError {
      return .failure(error.description)
    } catch let error as JSONError {
      return .failure(error.description)
    } catch {
      return .failure("Unknown Error")
    }
    return .success(nil)
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
    reporter.reportValue(EventName.Diagnose, EventType.Started, query)
    let diagnostics = self.fetchDiagnostics()
    reporter.reportValue(EventName.Diagnose, EventType.Ended, query)

    let subjects: [EventReporterSubject] = diagnostics.map { diagnostic in
      return SimpleSubject(
        EventName.Diagnostic,
        EventType.Discrete,
        ControlCoreSubject(diagnostic)
      )
    }
    return .success(CompositeSubject(subjects))
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
