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
  func run(reporter: EventReporter) -> CommandResult
}

extension Configuration {
  func buildSimulatorControl() throws -> FBSimulatorControl {
    let controlConfiguration = FBSimulatorControlConfiguration(deviceSetPath: self.deviceSetPath, options: self.managementOptions)
    let logger = FBControlCoreGlobalConfiguration.defaultLogger()
    return try FBSimulatorControl.withConfiguration(controlConfiguration, logger: logger)
  }
}

public extension Command {
  func runFromCLI() -> Int32 {
    let (reporter, result) = CommandRunner.bootstrap(self, writer: FileHandleWriter.stdOutWriter)
    switch result {
    case .Success:
      return 0
    case .Failure(let string):
      reporter.reportSimpleBridge(EventName.Failure, EventType.Discrete, string as NSString)
      return 1
    }
  }
}

private struct SequenceRunner : Runner {
  let runners: [Runner]

  func run(reporter: EventReporter) -> CommandResult {
    var output = CommandResult.Success
    for runner in runners {
      output = output.append(runner.run(reporter))
      switch output {
      case .Failure: return output
      default: continue
      }
    }
    return output
  }
}

private struct CommandRunner : Runner {
  let command: Command
  var defaults: Defaults?
  var control: FBSimulatorControl?

  func run(reporter: EventReporter) -> CommandResult {
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
        let runner = SequenceRunner(runners:
            actions.map { action in
              return ActionRunner(action: action, configuration: configuration, control: control, defaults: defaults, format: format, query: query)
            }
        )
        return runner.run(reporter)
      } catch DefaultsError.UnreadableRCFile(let string) {
        return .Failure("Unreadable .rc file " + string)
      } catch let error as NSError {
        return .Failure(error.description)
      }
    }
  }

  static func bootstrap(command: Command, writer: Writer) -> (EventReporter, CommandResult) {
    let reporter = command.createReporter(writer)
    let runner = CommandRunner(command: command, defaults: nil, control: nil)
    return (reporter, runner.run(reporter))
  }
}

struct ActionRunner : Runner {
  let action: Action
  let configuration: Configuration
  let control: FBSimulatorControl
  let defaults: Defaults
  let format: Format?
  let query: Query?

  func run(reporter: EventReporter) -> CommandResult {
    switch self.action {
    case .Listen(let server):
      return ServerRunner(configuration: self.configuration, control: control, defaults: self.defaults, format: self.format, query: self.query, serverConfiguration: server).run(reporter)
    case .Create(let configuration):
      return CreationRunner(configuration: self.configuration, control: control, defaults: self.defaults, format: self.format, simulatorConfiguration: configuration).run(reporter)
    default:
      do {
        let simulators = try Query.perform(self.control.set, query: self.query, defaults: self.defaults, action: self.action)
        let format = self.format ?? defaults.format
        let runners: [Runner] = simulators.map { simulator in
          SimulatorRunner(simulator: simulator, action: action.appendEnvironment(NSProcessInfo.processInfo().environment), format: format)
        }
        return SequenceRunner(runners: runners).run(reporter)
      } catch QueryError.PoolIsEmpty {
        reporter.reportSimpleBridge(EventName.Query, EventType.Discrete, "Pool is empty")
        return CommandResult.Success
      } catch let error as QueryError {
        return CommandResult.Failure(error.description)
      } catch {
        return CommandResult.Failure("Unknown Query Error")
      }
    }
  }
}

struct ServerRunner : Runner, CommandPerformer {
  let configuration: Configuration
  let control: FBSimulatorControl
  let defaults: Defaults
  let format: Format?
  let query: Query?
  let serverConfiguration: Server

  func run(reporter: EventReporter) -> CommandResult {
    let relayReporter = RelayReporter(reporter: reporter, subject: self.serverConfiguration)
    switch serverConfiguration {
    case .StdIO:
      StdIORelay(outputOptions: self.configuration.output, performer: self, reporter: relayReporter).start()
    case .Socket(let portNumber):
      SocketRelay(outputOptions: self.configuration.output, portNumber: portNumber, performer: self, reporter: relayReporter).start()
    case .Http(let portNumber):
      let performer = ActionPerformer(commandPerformer: self, configuration: self.configuration, query: self.query, format: self.format)
      HttpRelay(portNumber: portNumber, performer: performer, reporter: relayReporter).start()
    }
    return .Success
  }

  func perform(command: Command, reporter: EventReporter) -> CommandResult {
    return CommandRunner(command: command, defaults: self.defaults, control: self.control).run(reporter)
  }
}

struct CreationRunner : Runner {
  let configuration: Configuration
  let control: FBSimulatorControl
  let defaults: Defaults
  let format: Format?
  let simulatorConfiguration: FBSimulatorConfiguration

  func run(reporter: EventReporter) -> CommandResult {
    do {
      reporter.reportSimpleBridge(EventName.Create, EventType.Started, self.simulatorConfiguration)
      let simulator = try self.control.set.createSimulatorWithConfiguration(simulatorConfiguration)
      self.defaults.updateLastQuery(Query.UDID([simulator.udid]))
      reporter.reportSimpleBridge(EventName.Create, EventType.Ended, simulator)
      return CommandResult.Success
    } catch let error as NSError {
      return CommandResult.Failure("Failed to Create Simulator \(error.description)")
    }
  }
}

private struct SimulatorRunner : Runner {
  let simulator: FBSimulator
  let action: Action
  let format: Format

  func run(reporter: EventReporter) -> CommandResult {
    do {
      let translator = EventSinkTranslator(simulator: self.simulator, format: self.format, reporter: reporter)
      defer {
        translator.simulator.userEventSink = nil
      }

      return SimulatorRunner.makeActionPerformer(self.action, translator).perform()
    }
  }

  static func makeActionPerformer(action : Action, _ translator: EventSinkTranslator) -> SimulatorControlActionPerformer {
    let simulator = translator.simulator
    switch action {
    case .Approve(let bundleIDs):
      return SimulatorInteraction(translator: translator, name: EventName.Approve, subject: bundleIDs as NSArray) { interaction in
        interaction.authorizeLocationSettings(bundleIDs)
      }
    case .Boot(let maybeLaunchConfiguration):
      let launchConfiguration = maybeLaunchConfiguration ?? FBSimulatorLaunchConfiguration.defaultConfiguration()!
      return SimulatorInteraction(translator: translator, name: EventName.Boot, subject: launchConfiguration) { interaction in
        interaction.prepareForLaunch(launchConfiguration).bootSimulator(launchConfiguration)
      }
    case .Delete:
      return SimulatorAction(translator: translator, name: EventName.Delete, subject: simulator) {
        try simulator.set!.deleteSimulator(simulator)
      }
    case .Diagnose(let query, let format):
      return DiagnosticsInteraction(translator: translator, subject: query, query: query, format: format)
    case .Install(let application):
      return SimulatorInteraction(translator: translator, name: EventName.Install, subject: application) { interaction in
        interaction.installApplication(application)
      }
    case .Launch(let launch):
      return SimulatorInteraction(translator: translator, name: EventName.Launch, subject: launch) { interaction in
        if let appLaunch = launch as? FBApplicationLaunchConfiguration {
          interaction.launchApplication(appLaunch)
        }
        else if let agentLaunch = launch as? FBAgentLaunchConfiguration {
          interaction.launchAgent(agentLaunch)
        }
      }
    case .List:
      return SimulatorAction(translator: translator, name: EventName.List, subject: simulator) {
        translator.reportSimulator(EventName.List, simulator)
      }
    case .Open(let url):
      return SimulatorInteraction(translator: translator, name: EventName.Open, subject: simulator) { interaction in
        interaction.openURL(url)
      }
    case .Record(let start):
      return SimulatorInteraction(translator: translator, name: EventName.Record, subject: simulator) { interaction in
        if (start) {
          interaction.startRecordingVideo()
        } else {
          interaction.stopRecordingVideo()
        }
      }
    case .Relaunch(let appLaunch):
      return SimulatorInteraction(translator: translator, name: EventName.Relaunch, subject: appLaunch) { interaction in
        interaction.launchOrRelaunchApplication(appLaunch)
      }
    case .Search(let search):
      return SearchInteraction(translator: translator, search: search)
    case .Shutdown:
      return SimulatorAction(translator: translator, name: EventName.Shutdown, subject: simulator) {
        try simulator.set!.killSimulator(simulator)
      }
    case .Tap(let x, let y):
      return SimulatorInteraction(translator: translator, name: EventName.Tap, subject: simulator) { interaction in
        interaction.tap(x, y: y)
      }
    case .Terminate(let bundleID):
      return SimulatorInteraction(translator: translator, name: EventName.Record, subject: bundleID as NSString) { interaction in
        interaction.terminateApplicationWithBundleID(bundleID)
      }
    case .Upload(let diagnostics):
      return UploadInteraction(translator: translator, diagnostics: diagnostics)
    default:
      return SimulatorAction(translator: translator, name: EventName.Failure, subject: simulator) {
        assertionFailure("Unimplemented")
      }
    }
  }
}
