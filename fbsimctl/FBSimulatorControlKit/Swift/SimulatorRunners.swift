/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation

extension FileOutput {
  func makeWriter() throws -> FBDataConsumer {
    switch self {
    case let .path(path):
      return try FBFileWriter.syncWriter(forFilePath: path)
    case .standardOut:
      return FBFileWriter.syncWriter(withFileDescriptor: FileHandle.standardOutput.fileDescriptor, closeOnEndOfFile: false)
    }
  }
}

extension iOSRunnerContext {
  private func makeSimulatorConfiguratons(_ creationSpecification: CreationSpecification) -> [FBSimulatorConfiguration] {
    switch creationSpecification {
    case .allMissingDefaults:
      return simulatorControl.set.configurationsForAbsentDefaultSimulators()
    case let .individual(configuration):
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
    } catch {
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
    case let .clearKeychain(maybeBundleID):
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
        futures: [(simulator, simulator.set!.cloneSimulator(simulator, toDeviceSet: simulator.set!))]
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
        try simulator.focus().await()
      }
    case .keyboardOverride:
      return FutureRunner(
        reporter,
        .keyboardOverride,
        simulator.subject,
        simulator.setupKeyboard()
      )
    case let .open(url):
      return SimpleRunner(reporter, .open, FBEventReporterSubject(string: url.bridgedAbsoluteString)) {
        try simulator.open(url).await()
      }
    case let .relaunch(processLaunch):
      var appLaunch = FBApplicationLaunchConfiguration(bundleID: processLaunch.bundleID, bundleName: processLaunch.bundleName, arguments: processLaunch.arguments, environment: processLaunch.environment, output: processLaunch.output, launchMode: .relaunchIfRunning)
      if processLaunch.waitForDebugger {
        appLaunch = appLaunch.withWaitForDebugger(nil)
      }
      return FutureRunner(reporter, .relaunch, appLaunch.subject, simulator.launchApplication(appLaunch))
    case let .setLocation(latitude, longitude):
      return FutureRunner(
        reporter,
        .setLocation,
        simulator.subject,
        simulator.setLocationWithLatitude(latitude, longitude: longitude)
      )
    case let .upload(diagnostics):
      return UploadRunner(reporter, diagnostics)
    case let .watchdogOverride(bundleIDs, timeout):
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
    var diagnosticLocations: [(FBDiagnostic, URL)] = []
    for diagnostic in diagnostics {
      guard let localPath = diagnostic.asPath else {
        return .failure("Could not get a local path for diagnostic \(diagnostic)")
      }
      diagnosticLocations.append((diagnostic, URL.init(fileURLWithPath: localPath)))
    }

    let mediaPredicate = FBSimulatorMediaCommands.predicateForMediaPaths()
    let media = diagnosticLocations.filter { _, location in
      mediaPredicate.evaluate(with: location)
    }

    if media.count > 0 {
      let paths = media.map { $0.1 }
      let runner = FutureRunner(reporter, .upload, reporter.simulator.subject, reporter.simulator.addMedia(paths))
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
