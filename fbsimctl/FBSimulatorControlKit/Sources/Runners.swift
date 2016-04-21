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
import FBControlCore

protocol Runner {
  func run() -> CommandResult
}

extension Configuration {
  func buildSimulatorControl() throws -> FBSimulatorControl {
    let controlConfiguration = FBSimulatorControlConfiguration(deviceSetPath: self.deviceSetPath, options: self.managementOptions)
    let logger = FBControlCoreGlobalConfiguration.defaultLogger()
    return try FBSimulatorControl.withConfiguration(controlConfiguration, logger: logger)
  }
}

private struct SequenceRunner : Runner {
  let runners: [Runner]

  func run() -> CommandResult {
    var output = CommandResult.Success
    for runner in runners {
      output = output.append(runner.run())
      switch output {
      case .Failure: return output
      default: continue
      }
    }
    return output
  }
}

struct CommandRunner : Runner {
  let reporter: EventReporter
  let command: Command
  var defaults: Defaults?
  var control: FBSimulatorControl?

  func run() -> CommandResult {
    switch (self.command) {
    case .Help(_, let userSpecified, _):
      reporter.reportSimpleBridge(EventName.Help, EventType.Discrete, Command.getHelp() as NSString)
      if userSpecified {
        return .Success
      } else {
        return .Failure("")
      }
    case .Perform(let configuration, let actions, let query, let format):
      do {
        let defaults = try self.defaults ?? Defaults.create(configuration, logWriter: FileHandleWriter.stdOutWriter)
        let control = try self.control ?? defaults.configuration.buildSimulatorControl()
        let format = format ?? defaults.format
        let reporter = self.reporter
        let runner = SequenceRunner(runners:
            actions.map { action in
              return ActionRunner(
                reporter: reporter,
                action: action,
                configuration: configuration,
                control: control,
                defaults: defaults,
                format: format,
                query: query
              )
            }
        )
        return runner.run()
      } catch DefaultsError.UnreadableRCFile(let string) {
        return .Failure("Unreadable .rc file " + string)
      } catch let error as NSError {
        return .Failure(error.description)
      }
    }
  }

  static func bootstrap(command: Command, writer: Writer) -> (EventReporter, CommandResult) {
    let reporter = command.createReporter(writer)
    let runner = CommandRunner(reporter: reporter, command: command, defaults: nil, control: nil)
    return (reporter, runner.run())
  }
}

struct ActionRunner : Runner {
  let reporter: EventReporter
  let action: Action
  let configuration: Configuration
  let control: FBSimulatorControl
  let defaults: Defaults
  let format: Format
  let query: FBSimulatorQuery?

  func run() -> CommandResult {
    switch self.action {
    case .Listen(let server):
      return ServerRunner(
        reporter: self.reporter,
        configuration: self.configuration,
        control: control,
        defaults: self.defaults,
        format: self.format,
        query: self.query,
        serverConfiguration: server
      ).run()
    case .Create(let configuration):
      return CreationRunner(
        reporter: self.reporter,
        configuration: self.configuration,
        control: control,
        defaults: self.defaults,
        simulatorConfiguration: configuration
      ).run()
    default:
      if control.set.allSimulators.count == 0 {
        reporter.reportSimpleBridge(EventName.Query, EventType.Discrete, "No Devices in Device Set")
        return CommandResult.Success
      }
      guard let query = self.query ?? self.defaults.queryForAction(self.action) else {
        return CommandResult.Failure("No Query Provided")
      }
      let simulators = query.perform(self.control.set)
      if simulators.count == 0 {
        reporter.reportSimpleBridge(EventName.Query, EventType.Discrete, "No Matching Devices in Set")
        return CommandResult.Success
      }
      let runners: [Runner] = simulators.map { simulator in
        SimulatorRunner(
          reporter: self.reporter,
          simulator: simulator,
          action: action.appendEnvironment(NSProcessInfo.processInfo().environment),
          format: format
        )
      }

      defaults.updateLastQuery(query)
      return SequenceRunner(runners: runners).run()
    }
  }
}

struct ServerRunner : Runner, CommandPerformer {
  let reporter: EventReporter
  let configuration: Configuration
  let control: FBSimulatorControl
  let defaults: Defaults
  let format: Format?
  let query: FBSimulatorQuery?
  let serverConfiguration: Server

  func run() -> CommandResult {
    let relay = SynchronousRelay(relay: self.baseRelay, reporter: reporter)
    do {
      reporter.reportSimple(EventName.Listen, EventType.Started, serverConfiguration)
      try relay.start()
    } catch let error as CustomStringConvertible {
      return .Failure(error.description)
    } catch {
      return .Failure("An unknown error occurred running the server")
    }
    let _ = try? relay.stop()
    reporter.reportSimple(EventName.Listen, EventType.Ended, serverConfiguration)
    return .Success
  }

  var baseRelay: Relay { get {
    switch self.serverConfiguration {
    case .StdIO:
      return StdIORelay(outputOptions: self.configuration.outputOptions, performer: self)
    case .Socket(let portNumber):
      return SocketRelay(outputOptions: self.configuration.outputOptions, portNumber: portNumber, performer: self)
    case .Http(let portNumber):
      let query = self.query ?? self.defaults.queryForAction(Action.Listen(self.serverConfiguration))!
      let format = self.format ?? self.defaults.format
      let performer = ActionPerformer(commandPerformer: self, configuration: self.configuration, query: query, format: format)
      return HttpRelay(portNumber: portNumber, performer: performer)
    }
  }}

  func perform(command: Command, reporter: EventReporter) -> CommandResult {
    return CommandRunner(
      reporter: reporter,
      command: command,
      defaults: self.defaults,
      control: self.control
    ).run()
  }
}

struct CreationRunner : Runner {
  let reporter: EventReporter
  let configuration: Configuration
  let control: FBSimulatorControl
  let defaults: Defaults
  let simulatorConfiguration: FBSimulatorConfiguration

  func run() -> CommandResult {
    do {
      self.reporter.reportSimpleBridge(EventName.Create, EventType.Started, self.simulatorConfiguration)
      let simulator = try self.control.set.createSimulatorWithConfiguration(simulatorConfiguration)
      self.defaults.updateLastQuery(FBSimulatorQuery.udids([simulator.udid]))
      self.reporter.reportSimpleBridge(EventName.Create, EventType.Ended, simulator)
      return CommandResult.Success
    } catch let error as NSError {
      return CommandResult.Failure("Failed to Create Simulator \(error.description)")
    }
  }
}

private struct SimulatorRunner : Runner {
  let reporter: EventReporter
  let simulator: FBSimulator
  let action: Action
  let format: Format

  func run() -> CommandResult {
    do {
      let reporter = SimulatorReporter(simulator: self.simulator, format: self.format, reporter: self.reporter)
      defer {
        reporter.simulator.userEventSink = nil
      }

      return self.runner(reporter).run()
    }
  }

  func runner(reporter: SimulatorReporter) -> Runner {
    let simulator = reporter.simulator
    switch self.action {
    case .Approve(let bundleIDs):
      return SimulatorInteraction(reporter, EventName.Approve, ArraySubject(bundleIDs)) { interaction in
        interaction.authorizeLocationSettings(bundleIDs)
      }
    case .Boot(let maybeLaunchConfiguration):
      let launchConfiguration = maybeLaunchConfiguration ?? FBSimulatorLaunchConfiguration.defaultConfiguration()!
      return SimulatorInteraction(reporter, EventName.Boot, ControlCoreSubject(launchConfiguration)) { interaction in
        interaction.prepareForLaunch(launchConfiguration).bootSimulator(launchConfiguration)
      }
    case .ClearKeychain(let bundleID):
      return SimulatorInteraction(reporter, EventName.ClearKeychain, bundleID) { interaction in
        interaction.clearKeychainForApplication(bundleID)
      }
    case .Delete:
      return SimulatorAction(reporter, EventName.Delete, ControlCoreSubject(simulator)) {
        try simulator.set!.deleteSimulator(simulator)
      }
    case .Diagnose(let query, let format):
      return DiagnosticsInteraction(reporter, query, query, format)
    case .Install(let application):
      return SimulatorInteraction(reporter, EventName.Install, ControlCoreSubject(application)) { interaction in
        interaction.installApplication(application)
      }
    case .LaunchAgent(let launch):
      return SimulatorInteraction(reporter, EventName.Launch, ControlCoreSubject(launch)) { interaction in
        interaction.launchAgent(launch)
      }
    case .LaunchApp(let launch):
      return SimulatorInteraction(reporter, EventName.Launch, ControlCoreSubject(launch)) { interaction in
        interaction.launchApplication(launch)
      }
    case .LaunchXCTest(let launch, let bundlePath):
      return SimulatorInteraction(reporter, EventName.LaunchXCTest, ControlCoreSubject(launch)) { interaction in
        interaction.startTestRunnerLaunchConfiguration(launch, testBundlePath: bundlePath)
      }
    case .List:
      let format = reporter.format
      return SimulatorAction(reporter, nil, ControlCoreSubject(simulator)) {
        let subject = SimulatorSubject(simulator: simulator, format: format)
        reporter.reporter.reportSimple(EventName.List, EventType.Discrete, subject)
      }
    case .Open(let url):
      return SimulatorInteraction(reporter, EventName.Open, url.absoluteString) { interaction in
        interaction.openURL(url)
      }
    case .Record(let start):
      return SimulatorInteraction(reporter, EventName.Record, start) { interaction in
        if (start) {
          interaction.startRecordingVideo()
        } else {
          interaction.stopRecordingVideo()
        }
      }
    case .Relaunch(let appLaunch):
      return SimulatorInteraction(reporter, EventName.Relaunch, ControlCoreSubject(appLaunch)) { interaction in
        interaction.launchOrRelaunchApplication(appLaunch)
      }
    case .Search(let search):
      return SearchInteraction(reporter, search)
    case .Shutdown:
      return SimulatorAction(reporter, EventName.Shutdown, ControlCoreSubject(simulator)) {
        try simulator.set!.killSimulator(simulator)
      }
    case .Tap(let x, let y):
      return SimulatorInteraction(reporter, EventName.Tap, ControlCoreSubject(simulator)) { interaction in
        interaction.tap(x, y: y)
      }
    case .Terminate(let bundleID):
      return SimulatorInteraction(reporter, EventName.Record, bundleID) { interaction in
        interaction.terminateApplicationWithBundleID(bundleID)
      }
    case .Uninstall(let bundleID):
      return SimulatorInteraction(reporter, EventName.Uninstall, bundleID) { interaction in
        interaction.uninstallApplicationWithBundleID(bundleID)
      }
    case .Upload(let diagnostics):
      return UploadInteraction(reporter, diagnostics)
    default:
      return SimulatorAction(reporter, EventName.Failure, ControlCoreSubject(simulator)) {
        assertionFailure("Unimplemented")
      }
    }
  }
}
