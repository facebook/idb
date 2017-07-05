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

extension FileOutput {
  func makeWriter() throws -> FBFileWriter {
    switch self {
    case .path(let path):
      return try FBFileWriter(forFilePath: path, blocking: true)
    case .standardOut:
      return FBFileWriter(fileHandle: FileHandle.standardOutput, blocking: true)
    }
  }
}

struct SimulatorCreationRunner : Runner {
  let context: iOSRunnerContext<CreationSpecification>

  func run() -> CommandResult {
    do {
      for configuration in self.configurations {
        self.context.reporter.reportSimpleBridge(.create, .started, configuration)
        let simulator = try self.context.simulatorControl.set.createSimulator(with: configuration)
        self.context.defaults.updateLastQuery(FBiOSTargetQuery.udids([simulator.udid]))
        self.context.reporter.reportSimpleBridge(.create, .ended, simulator)
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
      return iOSTargetRunner.simple(reporter, .approve, StringsSubject(bundleIDs)) {
        try simulator.authorizeLocationSettings(bundleIDs)
      }
    case .clearKeychain(let maybeBundleID):
      return iOSTargetRunner.simple(reporter, .clearKeychain, ControlCoreSubject(simulator)) {
        if let bundleID = maybeBundleID {
          try simulator.killApplication(withBundleID: bundleID)
        }
        try simulator.clearKeychain()
      }
    case .delete:
      return iOSTargetRunner.simple(reporter, .delete, ControlCoreSubject(simulator)) {
        try simulator.set!.delete(simulator)
      }
    case .erase:
      return iOSTargetRunner.simple(reporter, .erase, ControlCoreSubject(simulator)) {
        try simulator.erase()
      }
    case .focus:
      return iOSTargetRunner.simple(reporter, .focus, ControlCoreSubject(simulator)) {
        try simulator.focus()
      }
    case .keyboardOverride:
      return iOSTargetRunner.simple(reporter, .keyboardOverride, ControlCoreSubject(simulator)) {
        try simulator.setupKeyboard()
      }
    case .open(let url):
      return iOSTargetRunner.simple(reporter, .open, url.bridgedAbsoluteString) {
        try simulator.open(url)
      }
    case .relaunch(let appLaunch):
      return iOSTargetRunner.simple(reporter, .relaunch, ControlCoreSubject(appLaunch)) {
        try simulator.launchOrRelaunchApplication(appLaunch)
      }
    case .search(let search):
      return SearchRunner(reporter, search)
    case .serviceInfo(let identifier):
      return ServiceInfoRunner(reporter: reporter, identifier: identifier)
    case .shutdown:
      return iOSTargetRunner.simple(reporter, .shutdown, ControlCoreSubject(simulator)) {
        try simulator.set!.kill(simulator)
      }
    case .setLocation(let latitude, let longitude):
      return iOSTargetRunner.simple(reporter, .setLocation, ControlCoreSubject(simulator)) {
        try simulator.setLocation(latitude, longitude: longitude)
      }
    case .upload(let diagnostics):
      return UploadRunner(reporter, diagnostics)
    case .watchdogOverride(let bundleIDs, let timeout):
      return iOSTargetRunner.simple(reporter, .watchdogOverride, StringsSubject(bundleIDs)) {
        try simulator.overrideWatchDogTimer(forApplications: bundleIDs, withTimeout: timeout)
      }
    default:
      return CommandResultRunner.unimplementedActionRunner(action, target: simulator, format: context.format)
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
    self.reporter.report(.search, .discrete, ControlCoreSubject(results))
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
    return .success(SimpleSubject(.serviceInfo, .discrete, ControlCoreSubject(processInfo)))
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
      let runner = iOSTargetRunner.simple(reporter, .upload, StringsSubject(paths)) {
        try FBUploadMediaStrategy(simulator: self.reporter.simulator).uploadMedia(paths)
      }
      let result = runner.run()
      switch result.outcome {
      case .failure: return result
      default: break
      }
    }

    let basePath = self.reporter.simulator.auxillaryDirectory
    let arbitraryPredicate = NSCompoundPredicate(notPredicateWithSubpredicate: mediaPredicate)
    let arbitrary = diagnosticLocations.filter{ arbitraryPredicate.evaluate(with: $0.1) }
    for (sourceDiagnostic, sourcePath) in arbitrary {
      guard let destinationPath = try? sourceDiagnostic.writeOut(toDirectory: basePath as String) else {
        return CommandResult.failure("Could not write out diagnostic \(sourcePath) to path")
      }
      let destinationDiagnostic = FBDiagnosticBuilder().updatePath(destinationPath).build()
      self.reporter.report(.upload, .discrete, ControlCoreSubject(destinationDiagnostic))
    }

    return .success(nil)
  }
}
