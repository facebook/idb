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

struct SimulatorCreationRunner : Runner {
  let context: iOSRunnerContext<CreationSpecification>

  func run() -> CommandResult {
    do {
      for configuration in self.configurations {
        self.context.reporter.reportSimpleBridge(EventName.Create, EventType.Started, configuration)
        let simulator = try self.context.simulatorControl.set.createSimulatorWithConfiguration(configuration)
        self.context.defaults.updateLastQuery(FBiOSTargetQuery.udids([simulator.udid]))
        self.context.reporter.reportSimpleBridge(EventName.Create, EventType.Ended, simulator)
      }
      return .Success(nil)
    } catch let error as NSError {
      return .Failure("Failed to Create Simulator \(error.description)")
    }
  }

  private var configurations: [FBSimulatorConfiguration] { get {
    switch self.context.value {
    case .AllMissingDefaults:
      return  self.context.simulatorControl.set.configurationsForAbsentDefaultSimulators()
    case .Individual(let configuration):
      return [configuration.simulatorConfiguration]
    }
  }}
}

struct SimulatorActionRunner : Runner {
  let context: iOSRunnerContext<(Action, FBSimulator)>

  func run() -> CommandResult {
    let (action, simulator) = self.context.value
    let reporter = SimulatorReporter(simulator: simulator, format: self.context.format, reporter: self.context.reporter)
    defer {
      simulator.userEventSink = nil
    }
    let context = self.context.replace((action, simulator, reporter))
    return SimulatorActionRunner.makeRunner(context).run()
  }

  static func makeRunner(context: iOSRunnerContext<(Action, FBSimulator, SimulatorReporter)>) -> Runner {
    let (action, simulator, reporter) = context.value
    let covariantTuple: (Action, FBiOSTarget, iOSReporter) = (action, simulator, reporter)
    if let runner = iOSActionProvider(context: context.replace(covariantTuple)).makeRunner() {
      return runner
    }

    switch action {
    case .Approve(let bundleIDs):
      return SimulatorInteractionRunner(reporter, EventName.Approve, StringsSubject(bundleIDs)) { interaction in
        interaction.authorizeLocationSettings(bundleIDs)
      }
    case .Boot(let maybeLaunchConfiguration):
      let launchConfiguration = maybeLaunchConfiguration ?? FBSimulatorLaunchConfiguration.defaultConfiguration()
      return SimulatorInteractionRunner(reporter, EventName.Boot, ControlCoreSubject(launchConfiguration)) { interaction in
        interaction.prepareForLaunch(launchConfiguration).bootSimulator(launchConfiguration)
      }
    case .ClearKeychain(let maybeBundleID):
      return SimulatorInteractionRunner(reporter, EventName.ClearKeychain, ControlCoreSubject(simulator)) { interaction in
        if let bundleID = maybeBundleID {
          interaction.terminateApplicationWithBundleID(bundleID)
        }
        interaction.clearKeychain()
      }
    case .Delete:
      return iOSTargetRunner(reporter, EventName.Delete, ControlCoreSubject(simulator)) {
        try simulator.set!.deleteSimulator(simulator)
      }
    case .Diagnose(let query, let format):
      return DiagnosticsRunner(reporter, query, query, format)
    case .Erase:
      return iOSTargetRunner(reporter, EventName.Erase, ControlCoreSubject(simulator)) {
        try simulator.erase()
      }
    case .LaunchAgent(let launch):
      return SimulatorInteractionRunner(reporter, EventName.Launch, ControlCoreSubject(launch)) { interaction in
        interaction.launchAgent(launch)
      }
    case .LaunchApp(let launch):
      return SimulatorInteractionRunner(reporter, EventName.Launch, ControlCoreSubject(launch)) { interaction in
        interaction.launchApplication(launch)
      }
    case .LaunchXCTest(let launch, let bundlePath, let timeout):
      return SimulatorInteractionRunner(reporter, EventName.LaunchXCTest, ControlCoreSubject(launch)) { interaction in
        let testLaunchConfiguration = FBTestLaunchConfiguration().withTestBundlePath(bundlePath).withApplicationLaunchConfiguration(launch).withUITesting(true)
        interaction.startTestWithLaunchConfiguration(testLaunchConfiguration)
        if let timeout = timeout {
            interaction.waitUntilAllTestRunnersHaveFinishedTestingWithTimeout(timeout)
        }
      }
    case .ListApps:
      return iOSTargetRunner(reporter, nil, ControlCoreSubject(simulator)) {
        let subject = ControlCoreSubject(simulator.installedApplications.map { $0.jsonSerializableRepresentation() } as NSArray)
        reporter.reporter.reportSimple(EventName.ListApps, EventType.Discrete, subject)
      }
    case .Open(let url):
      return SimulatorInteractionRunner(reporter, EventName.Open, url.bridgedAbsoluteString) { interaction in
        interaction.openURL(url)
      }
    case .Record(let start):
      return SimulatorInteractionRunner(reporter, EventName.Record, start) { interaction in
        if (start) {
          interaction.startRecordingVideo()
        } else {
          interaction.stopRecordingVideo()
        }
      }
    case .Relaunch(let appLaunch):
      return SimulatorInteractionRunner(reporter, EventName.Relaunch, ControlCoreSubject(appLaunch)) { interaction in
        interaction.launchOrRelaunchApplication(appLaunch)
      }
    case .Search(let search):
      return SearchRunner(reporter, search)
    case .Shutdown:
      return iOSTargetRunner(reporter, EventName.Shutdown, ControlCoreSubject(simulator)) {
        try simulator.set!.killSimulator(simulator)
      }
    case .Tap(let x, let y):
      return SimulatorInteractionRunner(reporter, EventName.Tap, ControlCoreSubject(simulator)) { interaction in
        interaction.tap(x, y: y)
      }
    case .SetLocation(let latitude, let longitude):
      return SimulatorInteractionRunner(reporter, EventName.SetLocation, ControlCoreSubject(simulator)) { interaction in
        interaction.setLocation(latitude, longitude: longitude)
      }
    case .Terminate(let bundleID):
      return SimulatorInteractionRunner(reporter, EventName.Terminate, bundleID) { interaction in
        interaction.terminateApplicationWithBundleID(bundleID)
      }
    case .Uninstall(let bundleID):
      return SimulatorInteractionRunner(reporter, EventName.Uninstall, bundleID) { interaction in
        interaction.uninstallApplicationWithBundleID(bundleID)
      }
    case .Upload(let diagnostics):
      return UploadRunner(reporter, diagnostics)
    case .WatchdogOverride(let bundleIDs, let timeout):
      return SimulatorInteractionRunner(reporter, EventName.WatchdogOverride, StringsSubject(bundleIDs)) { interaction in
        interaction.overrideWatchDogTimerForApplications(bundleIDs, withTimeout: timeout)
      }
    default:
      return CommandResultRunner.unimplementedActionRunner(action, target: simulator, format: context.format)
    }
  }
}

private struct SimulatorInteractionRunner : Runner {
  let reporter: SimulatorReporter
  let name: EventName
  let subject: EventReporterSubject
  let interaction: FBSimulatorInteraction throws -> Void

  init(_ reporter: SimulatorReporter, _ name: EventName, _ subject: EventReporterSubject, _ interaction: FBSimulatorInteraction throws -> Void) {
    self.reporter = reporter
    self.name = name
    self.subject = subject
    self.interaction = interaction
  }

  func run() -> CommandResult {
    let simulator = self.reporter.simulator
    let interaction = self.interaction
    let action = iOSTargetRunner(self.reporter, self.name, self.subject) {
      let interact = simulator.interact
      try interaction(interact)
      try interact.perform()
    }
    return action.run()
  }
}

private struct DiagnosticsRunner : Runner {
  let reporter: SimulatorReporter
  let subject: ControlCoreValue
  let query: FBSimulatorDiagnosticQuery
  let format: DiagnosticFormat

  init(_ reporter: SimulatorReporter, _ subject: ControlCoreValue, _ query: FBSimulatorDiagnosticQuery, _ format: DiagnosticFormat) {
    self.reporter = reporter
    self.subject = subject
    self.query = query
    self.format = format
  }

  func run() -> CommandResult {
    let diagnostics = self.fetchDiagnostics()

    reporter.reportValue(EventName.Diagnose, EventType.Started, query)
    for diagnostic in diagnostics {
      reporter.reportValue(EventName.Diagnostic, EventType.Discrete, diagnostic)
    }
    reporter.reportValue(EventName.Diagnose, EventType.Ended, query)
    return .Success(nil)
  }

  func fetchDiagnostics() -> [FBDiagnostic] {
    let diagnostics = self.reporter.simulator.diagnostics
    let format = self.format

    return query.perform(diagnostics).map { diagnostic in
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
  let reporter: SimulatorReporter
  let search: FBBatchLogSearch

  init(_ reporter: SimulatorReporter, _ search: FBBatchLogSearch) {
    self.reporter = reporter
    self.search = search
  }

  func run() -> CommandResult {
    let simulator = self.reporter.simulator
    let diagnostics = simulator.diagnostics.allDiagnostics()
    let results = search.search(diagnostics)
    self.reporter.report(EventName.Search, EventType.Discrete, ControlCoreSubject(results))
    return .Success(nil)
  }
}

private struct UploadRunner : Runner {
  let reporter: SimulatorReporter
  let diagnostics: [FBDiagnostic]

  init(_ reporter: SimulatorReporter, _ diagnostics: [FBDiagnostic]) {
    self.reporter = reporter
    self.diagnostics = diagnostics
  }

  func run() -> CommandResult {
    var diagnosticLocations: [(FBDiagnostic, String)] = []
    for diagnostic in diagnostics {
      guard let localPath = diagnostic.asPath else {
        return .Failure("Could not get a local path for diagnostic \(diagnostic)")
      }
      diagnosticLocations.append((diagnostic, localPath))
    }

    let mediaPredicate = NSPredicate.predicateForMediaPaths()
    let media = diagnosticLocations.filter { mediaPredicate.evaluateWithObject($0.1) }

    if media.count > 0 {
      let paths = media.map { $0.1 }
      let interaction = SimulatorInteractionRunner(self.reporter, EventName.Upload, StringsSubject(paths)) { interaction in
        interaction.uploadMedia(paths)
      }
      let result = interaction.run()
      switch result {
      case .Failure: return result
      default: break
      }
    }

    guard let basePath: NSString = self.reporter.simulator.auxillaryDirectory else {
        return CommandResult.Failure("Could not determine aux directory for simulator \(self.reporter.target) to path")
    }
    let arbitraryPredicate = NSCompoundPredicate(notPredicateWithSubpredicate: mediaPredicate)
    let arbitrary = diagnosticLocations.filter{ arbitraryPredicate.evaluateWithObject($0.1) }
    for (sourceDiagnostic, sourcePath) in arbitrary {
      guard let destinationPath = try? sourceDiagnostic.writeOutToDirectory(basePath as String) else {
        return CommandResult.Failure("Could not write out diagnostic \(sourcePath) to path")
      }
      let destinationDiagnostic = FBDiagnosticBuilder().updatePath(destinationPath).build()
      self.reporter.report(EventName.Upload, EventType.Discrete, ControlCoreSubject(destinationDiagnostic))
    }

    return .Success(nil)
  }
}
