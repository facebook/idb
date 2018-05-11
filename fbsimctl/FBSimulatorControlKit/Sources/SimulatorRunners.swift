/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import FBSimulatorControl
import Foundation

extension FileOutput {
  func makeWriter() throws -> FBFileWriter {
    switch self {
    case .path(let path):
      return try FBFileWriter.syncWriter(forFilePath: path)
    case .standardOut:
      return FBFileWriter.syncWriter(with: FileHandle.standardOutput)
    }
  }
}

extension iOSRunnerContext {
  private func makeSimulatorConfiguratons(_ creationSpecification: CreationSpecification) -> [FBSimulatorConfiguration] {
    switch creationSpecification {
    case .allMissingDefaults:
      return simulatorControl.set.configurationsForAbsentDefaultSimulators()
    case .individual(let configuration):
      return [configuration.simulatorConfiguration]
    }
  }

  func createSimulators(_ creationSpecification: CreationSpecification) -> [(ControlCoreValue, FBFuture<FBSimulator>)] {
    let configurations = makeSimulatorConfiguratons(creationSpecification)
    return configurations.map { configuration in
      let future = self.simulatorControl.set.createSimulator(with: configuration)
      return (configuration, future)
    }
  }
}

extension FBBitmapStreamingCommands {
  func startStreaming(configuration: FBBitmapStreamConfiguration, output: FileOutput) -> FBFuture<FBiOSTargetContinuation> {
    do {
      let writer = try output.makeWriter()
      let stream = try createStream(with: configuration).await()
      return stream.startStreaming(writer).mapReplace(stream) as! FBFuture<FBiOSTargetContinuation>
    } catch let error {
      return FBFuture(error: error)
    }
  }
}

struct SimulatorCreationRunner<T>: Runner {
  let context: iOSRunnerContext<T>
  let eventName: EventName
  let futures: [(ControlCoreValue, FBFuture<FBSimulator>)]

  func run() -> CommandResult {
    do {
      for (subject, future) in futures {
        context.reporter.reportSimpleBridge(eventName, .started, subject)
        let simulator = try future.await()
        context.defaults.updateLastQuery(FBiOSTargetQuery.udids([simulator.udid]))
        context.reporter.reportSimpleBridge(eventName, .ended, simulator)
      }
      return .success(nil)
    } catch let error as NSError {
      return .failure("Failed to Create Simulator \(error.description)")
    }
  }
}

struct SimulatorActionRunner: Runner {
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
    case .clearKeychain(let maybeBundleID):
      var futures: [FBFuture<NSNull>] = []
      if let bundleID = maybeBundleID {
        futures.append(simulator.killApplication(withBundleID: bundleID))
      }
      futures.append(simulator.clearKeychain())
      return FutureRunner(
        reporter,
        .clearKeychain,
        simulator.subject,
        FBFuture(futures: futures)
      )
    case .clone:
      return SimulatorCreationRunner(
        context: context,
        eventName: .clone,
        futures: [(simulator, simulator.set!.cloneSimulator(simulator))]
      )
    case .delete:
      return FutureRunner(
        reporter,
        .delete,
        simulator.subject,
        simulator.set!.delete(simulator)
      )
    case .focus:
      return SimpleRunner(reporter, .focus, simulator.subject) {
        try simulator.focus()
      }
    case .keyboardOverride:
      return FutureRunner(
        reporter,
        .keyboardOverride,
        simulator.subject,
        simulator.setupKeyboard()
      )
    case .open(let url):
      return SimpleRunner(reporter, .open, FBEventReporterSubject(string: url.bridgedAbsoluteString)) {
        try simulator.open(url)
      }
    case .relaunch(let appLaunch):
      return FutureRunner(reporter, .relaunch, appLaunch.subject, simulator.launchOrRelaunchApplication(appLaunch))
    case .setLocation(let latitude, let longitude):
      return FutureRunner(
        reporter,
        .setLocation,
        simulator.subject,
        simulator.setLocationWithLatitude(latitude, longitude: longitude)
      )
    case .upload(let diagnostics):
      return UploadRunner(reporter, diagnostics)
    case .watchdogOverride(let bundleIDs, let timeout):
      return FutureRunner(
        reporter,
        .watchdogOverride,
        FBEventReporterSubject(strings: bundleIDs),
        simulator.overrideWatchDogTimer(forApplications: bundleIDs, withTimeout: timeout)
      )
    default:
      return CommandResultRunner.unimplementedActionRunner(action, target: simulator, format: context.format)
    }
  }
}

private struct UploadRunner: Runner {
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
    let media = diagnosticLocations.filter { _, location in
      mediaPredicate.evaluate(with: location)
    }

    if media.count > 0 {
      let paths = media.map { $0.1 }
      let runner = SimpleRunner(reporter, .upload, FBEventReporterSubject(strings: paths)) {
        try FBUploadMediaStrategy(simulator: self.reporter.simulator).uploadMedia(paths)
      }
      let result = runner.run()
      switch result.outcome {
      case .failure: return result
      default: break
      }
    }

    let basePath = reporter.simulator.auxillaryDirectory
    let arbitraryPredicate = NSCompoundPredicate(notPredicateWithSubpredicate: mediaPredicate)
    let arbitrary = diagnosticLocations.filter { arbitraryPredicate.evaluate(with: $0.1) }
    for (sourceDiagnostic, sourcePath) in arbitrary {
      guard let destinationPath = try? sourceDiagnostic.writeOut(toDirectory: basePath as String) else {
        return CommandResult.failure("Could not write out diagnostic \(sourcePath) to path")
      }
      let destinationDiagnostic = FBDiagnosticBuilder().updatePath(destinationPath).build()
      reporter.report(.upload, .discrete, destinationDiagnostic.subject)
    }

    return .success(nil)
  }
}
