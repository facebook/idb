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

protocol Runner {
  func run(reporter: EventReporter) -> ActionResult
}

extension Configuration {
  func buildSimulatorControl() throws -> FBSimulatorControl {
    let controlConfiguration = FBSimulatorControlConfiguration(deviceSetPath: self.deviceSetPath, options: self.managementOptions)
    let logger = FBSimulatorControlGlobalConfiguration.defaultLogger()
    return try FBSimulatorControl.withConfiguration(controlConfiguration, logger: logger)
  }
}

public extension Command {
  func runFromCLI() -> Int32 {
    let writer = FileHandleWriter.stdOutWriter
    switch CommandBootstrap(command: self, writer: writer).bootstrap() {
    case .Success:
      return 0
    case .Failure(let string):
      writer.write(string)
      return 1
    }
  }
}

private struct CommandBootstrap {
  let command: Command
  let writer: Writer

  func bootstrap() -> ActionResult {
    do {
      switch (self.command) {
      case .Help(let userSpecified, _):
        self.writer.write(Command.getHelp())
        if userSpecified {
          return .Success
        } else {
          return .Failure("")
        }
      case .Perform(let configuration, let actions, let query, let format):
        let reporter = configuration.options.createReporter(self.writer)
        let defaults = try Defaults.create(configuration, logWriter: FileHandleWriter.stdOutWriter)
        let control = try defaults.configuration.buildSimulatorControl()
        return SequenceRunner(runners:
          actions.map { action in
            return ActionRunner(action: action, configuration: configuration, control: control, defaults: defaults, format: format, query: query)
          }
        ).run(reporter)
      }
    } catch DefaultsError.UnreadableRCFile(let string) {
      return .Failure("Unreadable .rc file " + string)
    } catch let error as NSError {
      return .Failure(error.description)
    }
  }
}

private struct SequenceRunner : Runner {
  let runners: [Runner]

  func run(reporter: EventReporter) -> ActionResult {
    var output = ActionResult.Success
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

struct ActionRunner : Runner {
  let action: Action
  let configuration: Configuration
  let control: FBSimulatorControl
  let defaults: Defaults
  let format: Format?
  let query: Query?

  func run(reporter: EventReporter) -> ActionResult {
    switch self.action {
    case .Listen(let server):
      return ServerRunner(configuration: self.configuration, control: control, defaults: self.defaults, format: self.format, query: self.query, serverConfiguration: server).run(reporter)
    case .Create(let configuration):
      return CreationRunner(configuration: self.configuration, control: control, defaults: self.defaults, format: self.format, simulatorConfiguration: configuration).run(reporter)
    default:
      do {
        let simulators = try Query.perform(self.control.simulatorPool, query: self.query, defaults: self.defaults, action: self.action)
        let format = self.format ?? defaults.format
        let runners: [Runner] = simulators.map { simulator in
          SimulatorRunner(simulator: simulator, configuration: self.configuration, action: action.appendEnvironment(NSProcessInfo.processInfo().environment), format: format)
        }
        return SequenceRunner(runners: runners).run(reporter)
      } catch let error as QueryError {
        return ActionResult.Failure(error.description)
      } catch {
        return ActionResult.Failure("Unknown Query Error")
      }
    }
  }
}

struct ServerRunner : Runner, ActionPerformer {
  let configuration: Configuration
  let control: FBSimulatorControl
  let defaults: Defaults
  let format: Format?
  let query: Query?
  let serverConfiguration: Server

  func run(reporter: EventReporter) -> ActionResult {
    let relayReporter = RelayReporter(reporter: reporter, subject: self.serverConfiguration)
    switch serverConfiguration {
    case .StdIO:
      StdIORelay(configuration: self.configuration, performer: self, reporter: relayReporter).start()
    case .Socket(let portNumber):
      SocketRelay(configuration: self.configuration, portNumber: portNumber, performer: self, reporter: relayReporter).start()
    case .Http(let portNumber):
      HttpRelay(portNumber: portNumber, performer: self, reporter: relayReporter).start()
    }
    return .Success
  }

  func perform(action: Action, reporter: EventReporter) -> ActionResult {
    return ActionRunner(action: action, configuration: self.configuration, control: self.control, defaults: self.defaults, format: self.format, query: self.query).run(reporter)
  }
}

struct CreationRunner : Runner {
  let configuration: Configuration
  let control: FBSimulatorControl
  let defaults: Defaults
  let format: Format?
  let simulatorConfiguration: FBSimulatorConfiguration

  func run(reporter: EventReporter) -> ActionResult {
    do {
      let options = FBSimulatorAllocationOptions.Create
      reporter.reportSimpleBridge(EventName.Create, EventType.Started, self.simulatorConfiguration)
      let simulator = try self.control.simulatorPool.allocateSimulatorWithConfiguration(simulatorConfiguration, options: options)
      self.defaults.updateLastQuery(Query.UDID([simulator.udid]))
      reporter.reportSimpleBridge(EventName.Create, EventType.Ended, simulator)
      return ActionResult.Success
    } catch let error as NSError {
      return ActionResult.Failure("Failed to Create Simulator \(error.description)")
    }
  }
}

private struct SimulatorRunner : Runner {
  let simulator: FBSimulator
  let configuration: Configuration
  let action: Action
  let format: Format

  func run(reporter: EventReporter) -> ActionResult {
    do {
      let translator = EventSinkTranslator(simulator: self.simulator, format: self.format, reporter: reporter)
      defer {
        translator.simulator.userEventSink = nil
      }

      switch self.action {
      case .List:
        translator.reportSimulator(EventName.List, simulator)
      case .Approve(let bundleIDs):
        try interactWithSimulator(translator, EventName.Approve, bundleIDs as NSArray) { interaction in
          interaction.authorizeLocationSettings(bundleIDs)
        }
      case .Boot(let maybeLaunchConfiguration):
        let launchConfiguration = maybeLaunchConfiguration ?? FBSimulatorLaunchConfiguration.defaultConfiguration()!
        try interactWithSimulator(translator, EventName.Boot, launchConfiguration) { interaction in
          interaction.prepareForLaunch(launchConfiguration).bootSimulator(launchConfiguration)
        }
      case .Shutdown:
        try interactWithSimulator(translator, EventName.Shutdown, self.simulator) { interaction in
          interaction.shutdownSimulator()
        }
      case .Diagnose:
        let logs = simulator.diagnostics.allDiagnostics().map{ $0.jsonSerializableRepresentation() }
        translator.reportSimulator(EventName.Diagnose, EventType.Discrete, logs as NSArray)
      case .Delete:
        translator.reportSimulator(EventName.Delete, EventType.Started, self.simulator)
        try simulator.pool!.deleteSimulator(simulator)
        translator.reportSimulator(EventName.Delete, EventType.Ended, self.simulator)
      case .Install(let application):
        try interactWithSimulator(translator, EventName.Install, application) { interaction in
          interaction.installApplication(application)
        }
      case .Launch(let launch):
        try interactWithSimulator(translator, EventName.Launch, launch) { interaction in
          if let appLaunch = launch as? FBApplicationLaunchConfiguration {
            interaction.launchApplication(appLaunch)
          }
          else if let agentLaunch = launch as? FBAgentLaunchConfiguration {
            interaction.launchAgent(agentLaunch)
          }
        }
      case .Relaunch(let appLaunch):
        try interactWithSimulator(translator, EventName.Relaunch, appLaunch) { interaction in
          interaction.launchOrRelaunchApplication(appLaunch)
        }
      case .Terminate(let bundleID):
        try interactWithSimulator(translator, EventName.Relaunch, bundleID as NSString) { interaction in
          interaction.terminateApplicationWithBundleID(bundleID)
        }
      default:
        assertionFailure("Unhandled")
      }
    } catch let error as NSError {
      return .Failure(error.description)
    } catch let error as JSONError {
      return .Failure(error.description)
    }
    return .Success
  }

  func interactWithSimulator(translator: EventSinkTranslator, _ eventName: EventName, _ subject: SimulatorControlSubject, interact: FBSimulatorInteraction -> Void) throws {
    translator.reportSimulator(eventName, EventType.Started, subject)
    let interaction = translator.simulator.interact()
    interact(interaction)
    try interaction.performInteraction()
    translator.reportSimulator(eventName, EventType.Ended, subject)
  }
}
