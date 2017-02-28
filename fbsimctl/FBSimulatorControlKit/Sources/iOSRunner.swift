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
    case .install(let appPath, let codeSign):
      return iOSTargetRunner(reporter, EventName.Install, ControlCoreSubject(appPath as NSString)) {
        let (extractedAppPath, cleanupDirectory) = try FBApplicationDescriptor.findOrExtract(atPath: appPath)
        if codeSign {
          try FBCodesignProvider.codeSignCommandWithAdHocIdentity().recursivelySignBundle(atPath: extractedAppPath)
        }
        try target.installApplication(withPath: extractedAppPath)
        if let cleanupDirectory = cleanupDirectory {
          try? FileManager.default.removeItem(at: cleanupDirectory)
        }
      }
    case .uninstall(let appBundleID):
      return iOSTargetRunner(reporter, EventName.Uninstall,ControlCoreSubject(appBundleID as NSString)) {
        try target.uninstallApplication(withBundleID: appBundleID)
      }
    case .launchApp(let appLaunch):
      return iOSTargetRunner(reporter, EventName.Launch, ControlCoreSubject(appLaunch)) {
        try target.launchApplication(appLaunch)
      }
    case .launchXCTest(var configuration):
      // Always initialize for UI Testing until we make this optional
      configuration = configuration.withUITesting(true)
      return iOSTargetRunner(reporter, EventName.LaunchXCTest, ControlCoreSubject(configuration)) {
        try target.startTest(with: configuration)

        if configuration.timeout > 0 {
          try target.waitUntilAllTestRunnersHaveFinishedTesting(withTimeout: configuration.timeout)
        }
      }
    case .listApps:
      return iOSTargetRunner(reporter, nil, ControlCoreSubject(target as! ControlCoreValue)) {
        let subject = ControlCoreSubject(target.installedApplications().map { $0.jsonSerializableRepresentation() }  as NSArray)
        reporter.reporter.reportSimple(EventName.ListApps, EventType.Discrete, subject)
      }
    case .record(let start):
      return iOSTargetRunner(reporter, EventName.Record, start) {
        if start {
          try target.startRecording()
        } else {
          try target.stopRecording()
        }
      }
    case .terminate(let bundleID):
      return iOSTargetRunner(reporter, EventName.Terminate, ControlCoreSubject(bundleID as NSString)) {
        try target.killApplication(withBundleID: bundleID)
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
  let action: (Void) throws -> Void

  init(_ reporter: iOSReporter, _ name: EventName?, _ subject: EventReporterSubject, _ action: @escaping (Void) throws -> Void) {
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
