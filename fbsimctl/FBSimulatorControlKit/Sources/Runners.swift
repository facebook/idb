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
      case .Help:
        self.writer.write(Command.getHelp())
        return .Success
      case .Listen(let configuration, let serverConfiguration):
        let reporter = configuration.options.createReporter(self.writer)
        let defaults = try Defaults.create(configuration, logWriter: FileHandleWriter.stdOutWriter)
        let control = try defaults.configuration.buildSimulatorControl()
        return ServerRunner(control: control, configuration: configuration, defaults: defaults, serverConfiguration: serverConfiguration).run(reporter)
      case .Perform(let configuration, let action):
        let reporter = configuration.options.createReporter(self.writer)
        let defaults = try Defaults.create(configuration, logWriter: FileHandleWriter.stdOutWriter)
        let control = try defaults.configuration.buildSimulatorControl()
        return ActionRunner(control: control, configuration: configuration, defaults: defaults, action: action).run(reporter)
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

private struct ActionRunner : Runner {
  let control: FBSimulatorControl
  let configuration: Configuration
  let defaults: Defaults
  let action: Action

  func run(reporter: EventReporter) -> ActionResult {
    switch self.action {
    case .Interact(let interactions, let query, let format):
      return InteractionRunner(control: control, configuration: self.configuration, defaults: defaults, interactions: interactions, query: query, format: format).run(reporter)
    case .Create(let configuration, let format):
      return CreationRunner(control: control, configuration: self.configuration, simulatorConfiguration: configuration, format: format ?? self.defaults.format).run(reporter)
    }
  }
}

class ServerRunner : Runner, ActionPerformer {
  let control: FBSimulatorControl
  let configuration: Configuration
  let defaults: Defaults
  let serverConfiguration: Server

  init(control: FBSimulatorControl, configuration: Configuration, defaults: Defaults, serverConfiguration: Server) {
    self.control = control
    self.configuration = configuration
    self.defaults = defaults
    self.serverConfiguration = serverConfiguration
  }

  func run(reporter: EventReporter) -> ActionResult {
    reporter.reportSimple(EventName.Listen, EventType.Started, self.serverConfiguration)
    switch serverConfiguration {
    case .StdIO:
      StdIORelay(configuration: self.configuration, performer: self).start()
    case .Socket(let portNumber):
      SocketRelay(configuration: self.configuration, portNumber: portNumber, performer: self).start()
    case .Http(let query, let portNumber):
      HttpRelay(query: query, portNumber: portNumber, performer: self).start()
    }
    reporter.reportSimple(EventName.Listen, EventType.Ended, self.serverConfiguration)
    return .Success
  }

  func perform(action: Action, reporter: EventReporter) -> ActionResult {
    return ActionRunner(control: self.control, configuration: self.configuration, defaults: self.defaults, action: action).run(reporter)
  }
}

struct InteractionRunner : Runner {
  let control: FBSimulatorControl
  let configuration: Configuration
  let defaults: Defaults
  let interactions: [Interaction]
  let query: Query?
  let format: Format?

  func run(reporter: EventReporter) -> ActionResult {
    do {
      let simulators = try Query.perform(self.control.simulatorPool, query: self.query, defaults: self.defaults)
      let format = self.format ?? defaults.format
      let runners: [Runner] = self.interactions.flatMap { interaction in
        return simulators.map { simulator in
          SimulatorRunner(simulator: simulator, configuration: self.configuration, interaction: interaction.appendEnvironment(NSProcessInfo.processInfo().environment), format: format)
        }
      }
      return SequenceRunner(runners: runners).run(reporter)
    } catch let error as QueryError {
      return ActionResult.Failure(error.description)
    } catch {
      return ActionResult.Failure("Unknown Query Error")
    }
  }
}

struct CreationRunner : Runner {
  let control: FBSimulatorControl
  let configuration: Configuration
  let simulatorConfiguration: FBSimulatorConfiguration
  let format: Format

  func run(reporter: EventReporter) -> ActionResult {
    do {
      let options = FBSimulatorAllocationOptions.Create
      reporter.reportSimpleBridge(EventName.Create, EventType.Started, self.simulatorConfiguration)
      let simulator = try self.control.simulatorPool.allocateSimulatorWithConfiguration(simulatorConfiguration, options: options)
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
  let interaction: Interaction
  let format: Format

  func run(reporter: EventReporter) -> ActionResult {
    do {
      let translator = EventSinkTranslator(simulator: self.simulator, format: self.format, reporter: reporter)
      defer {
        translator.simulator.userEventSink = nil
      }

      switch self.interaction {
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
        let logs = simulator.diagnostics.allDiagnostics() as! [FBSimulatorDiagnostics]
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
