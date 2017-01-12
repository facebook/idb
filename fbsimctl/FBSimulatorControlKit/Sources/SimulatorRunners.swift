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
        let simulator = try self.context.simulatorControl.set.createSimulator(with: configuration)
        self.context.defaults.updateLastQuery(FBiOSTargetQuery.udids([simulator.udid]))
        self.context.reporter.reportSimpleBridge(EventName.Create, EventType.Ended, simulator)
      }
      return .success(nil)
    } catch let error as NSError {
      return .failure("Failed to Create Simulator \(error.description)")
    }
  }

  fileprivate var configurations: [FBSimulatorConfiguration] { get {
    switch self.context.value {
    case .allMissingDefaults:
      return  self.context.simulatorControl.set.configurationsForAbsentDefaultSimulators()
    case .individual(let configuration):
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

  static func makeRunner(_ context: iOSRunnerContext<(Action, FBSimulator, SimulatorReporter)>) -> Runner {
    let (action, simulator, reporter) = context.value
    let covariantTuple: (Action, FBiOSTarget, iOSReporter) = (action, simulator, reporter)
    if let runner = iOSActionProvider(context: context.replace(covariantTuple)).makeRunner() {
      return runner
    }

    switch action {
    case .approve(let bundleIDs):
      return SimulatorInteractionRunner(reporter, EventName.Approve, StringsSubject(bundleIDs)) { interaction in
        interaction.authorizeLocationSettings(bundleIDs)
      }
    case .boot(let maybeBootConfiguration):
      let bootConfiguration = maybeBootConfiguration ?? FBSimulatorBootConfiguration.default()
      return SimulatorInteractionRunner(reporter, EventName.Boot, ControlCoreSubject(bootConfiguration)) { interaction in
        interaction.bootSimulator(bootConfiguration)
      }
    case .clearKeychain(let maybeBundleID):
      return SimulatorInteractionRunner(reporter, EventName.ClearKeychain, ControlCoreSubject(simulator)) { interaction in
        if let bundleID = maybeBundleID {
          interaction.terminateApplication(withBundleID: bundleID)
        }
        interaction.clearKeychain()
      }
    case .delete:
      return iOSTargetRunner(reporter, EventName.Delete, ControlCoreSubject(simulator)) {
        try simulator.set!.delete(simulator)
      }
    case .erase:
      return iOSTargetRunner(reporter, EventName.Erase, ControlCoreSubject(simulator)) {
        try simulator.erase()
      }
    case .keyboardOverride:
      return SimulatorInteractionRunner(reporter, EventName.KeyboardOverride, ControlCoreSubject(simulator)) { interaction in
        interaction.setupKeyboard()
      }
    case .launchAgent(let launch):
      return SimulatorInteractionRunner(reporter, EventName.Launch, ControlCoreSubject(launch)) { interaction in
        interaction.launchAgent(launch)
      }
    case .launchApp(let launch):
      return SimulatorInteractionRunner(reporter, EventName.Launch, ControlCoreSubject(launch)) { interaction in
        interaction.launchApplication(launch)
      }
    case .launchXCTest(var configuration):
      // Always initialize for UI Testing until we make this optional
      configuration = configuration.withUITesting(true)
      return SimulatorInteractionRunner(reporter, EventName.LaunchXCTest, ControlCoreSubject(configuration)) { interaction in
        interaction.startTest(with: configuration)

        if configuration.timeout > 0 {
            interaction.waitUntilAllTestRunnersHaveFinishedTesting(withTimeout: configuration.timeout)
        }
      }
    case .open(let url):
      return SimulatorInteractionRunner(reporter, EventName.Open, url.bridgedAbsoluteString) { interaction in
        interaction.open(url)
      }
    case .relaunch(let appLaunch):
      return SimulatorInteractionRunner(reporter, EventName.Relaunch, ControlCoreSubject(appLaunch)) { interaction in
        interaction.launchOrRelaunchApplication(appLaunch)
      }
    case .search(let search):
      return SearchRunner(reporter, search)
    case .serviceInfo(let identifier):
      return ServiceInfoRunner(reporter: reporter, identifier: identifier)
    case .shutdown:
      return iOSTargetRunner(reporter, EventName.Shutdown, ControlCoreSubject(simulator)) {
        try simulator.set!.kill(simulator)
      }
    case .tap(let x, let y):
      return SimulatorInteractionRunner(reporter, EventName.Tap, ControlCoreSubject(simulator)) { interaction in
        interaction.tap(x, y: y)
      }
    case .setLocation(let latitude, let longitude):
      return SimulatorInteractionRunner(reporter, EventName.SetLocation, ControlCoreSubject(simulator)) { interaction in
        interaction.setLocation(latitude, longitude: longitude)
      }
    case .upload(let diagnostics):
      return UploadRunner(reporter, diagnostics)
    case .watchdogOverride(let bundleIDs, let timeout):
      return SimulatorInteractionRunner(reporter, EventName.WatchdogOverride, StringsSubject(bundleIDs)) { interaction in
        interaction.overrideWatchDogTimer(forApplications: bundleIDs, withTimeout: timeout)
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
  let interaction:(FBSimulatorInteraction)throws -> Void

  init(_ reporter: SimulatorReporter, _ name: EventName, _ subject: EventReporterSubject, _ interaction: @escaping (FBSimulatorInteraction) throws -> Void) {
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
    return .success(nil)
  }
}

private struct ServiceInfoRunner : Runner {
  let reporter: SimulatorReporter
  let identifier: String

  func run() -> CommandResult {
    var pid: pid_t = 0
    guard let _ = try? self.reporter.simulator.launchctl.serviceName(forBundleID: self.identifier, processIdentifierOut: &pid) else {
      return .failure("Could not get service for name \(identifier)")
    }
    guard let processInfo = self.reporter.simulator.processFetcher.processFetcher.processInfo(for: pid) else {
      return .failure("Could not get process info for pid \(pid)")
    }
    return .success(SimpleSubject(EventName.ServiceInfo, EventType.Discrete, ControlCoreSubject(processInfo)))
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
        return .failure("Could not get a local path for diagnostic \(diagnostic)")
      }
      diagnosticLocations.append((diagnostic, localPath))
    }

    let mediaPredicate = NSPredicate.forMediaPaths()
    let media = diagnosticLocations.filter { (_, location) in
      mediaPredicate.evaluate(with: location)
    }

    if media.count > 0 {
      let paths = media.map { $0.1 }
      let runner = iOSTargetRunner(reporter, EventName.Upload, StringsSubject(paths)) {
        try FBUploadMediaStrategy(simulator: self.reporter.simulator).uploadMedia(paths)
      }
      let result = runner.run()
      switch result {
      case .failure: return result
      default: break
      }
    }

    guard let basePath: NSString = self.reporter.simulator.auxillaryDirectory as NSString? else {
        return CommandResult.failure("Could not determine aux directory for simulator \(self.reporter.target) to path")
    }
    let arbitraryPredicate = NSCompoundPredicate(notPredicateWithSubpredicate: mediaPredicate)
    let arbitrary = diagnosticLocations.filter{ arbitraryPredicate.evaluate(with: $0.1) }
    for (sourceDiagnostic, sourcePath) in arbitrary {
      guard let destinationPath = try? sourceDiagnostic.writeOut(toDirectory: basePath as String) else {
        return CommandResult.failure("Could not write out diagnostic \(sourcePath) to path")
      }
      let destinationDiagnostic = FBDiagnosticBuilder().updatePath(destinationPath).build()
      self.reporter.report(EventName.Upload, EventType.Discrete, ControlCoreSubject(destinationDiagnostic))
    }

    return .success(nil)
  }
}
