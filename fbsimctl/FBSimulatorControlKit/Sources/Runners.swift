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
      case .Interactive(let configuration, let port):
        let reporter = configuration.options.createReporter(self.writer)
        let defaults = try Defaults.create(configuration, logWriter: FileHandleWriter.stdOutWriter)
        let control = try defaults.configuration.buildSimulatorControl()
        return InteractiveRunner(control: control, configuration: configuration, defaults: defaults, portNumber: port).run(reporter)
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

class InteractiveRunner : Runner, RelayTransformer {
  let control: FBSimulatorControl
  let configuration: Configuration
  let defaults: Defaults
  let portNumber: Int?

  init(control: FBSimulatorControl, configuration: Configuration, defaults: Defaults, portNumber: Int?) {
    self.control = control
    self.configuration = configuration
    self.portNumber = portNumber
    self.defaults = defaults
  }

  func run(reporter: EventReporter) -> ActionResult {
    if let portNumber = self.portNumber {
      reporter.report(LogEvent("Starting Socket server on \(portNumber)", level: Constants.asl_level_info()))
      SocketRelay(configuration: self.configuration, portNumber: portNumber, transformer: self).start()
      reporter.report(LogEvent("Ending Socket Server", level: Constants.asl_level_info()))
    } else {
      reporter.report(LogEvent("Starting local interactive mode, listening on stdin", level: Constants.asl_level_info()))
      StdIORelay(configuration: self.configuration, transformer: self).start()
      reporter.report(LogEvent("Ending local interactive mode", level: Constants.asl_level_info()))
    }
    return .Success
  }

  func transform(input: String, reporter: EventReporter) -> ActionResult {
    do {
      let arguments = Arguments.fromString(input)
      let (_, action) = try Action.parser().parse(arguments)
      let runner = ActionRunner(control: self.control, configuration: self.configuration, defaults: self.defaults, action: action)
      return runner.run(reporter)
    } catch let error as ParseError {
      return .Failure("Error: \(error.description)")
    } catch let error as NSError {
      return .Failure(error.description)
    }
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
      reporter.reportSimple(EventName.Create, EventType.Started, self.simulatorConfiguration)
      let simulator = try self.control.simulatorPool.allocateSimulatorWithConfiguration(simulatorConfiguration, options: options)
      reporter.reportSimple(EventName.Create, EventType.Ended, simulator)
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
        translator.reportSimulator(EventName.Approve, EventType.Started, [bundleIDs] as NSArray)
        try simulator.interact().authorizeLocationSettings(bundleIDs).performInteraction()
        translator.reportSimulator(EventName.Approve, EventType.Ended, [bundleIDs] as NSArray)
      case .Boot(let maybeLaunchConfiguration):
        let launchConfiguration = maybeLaunchConfiguration ?? FBSimulatorLaunchConfiguration.defaultConfiguration()!
        translator.reportSimulator(EventName.Boot, EventType.Started, launchConfiguration)
        try simulator.interact().prepareForLaunch(launchConfiguration).bootSimulator(launchConfiguration).performInteraction()
        translator.reportSimulator(EventName.Boot, EventType.Ended, launchConfiguration)
      case .Shutdown:
        translator.reportSimulator(EventName.Shutdown, EventType.Started, self.simulator)
        try simulator.interact().shutdownSimulator().performInteraction()
        translator.reportSimulator(EventName.Shutdown, EventType.Ended, self.simulator)
      case .Diagnose:
        let logs = simulator.logs.allLogs() as! [FBSimulatorLogs]
        translator.reportSimulator(EventName.Diagnostic, EventType.Discrete, logs)
      case .Delete:
        translator.reportSimulator(EventName.Delete, EventType.Started, self.simulator)
        try simulator.pool!.deleteSimulator(simulator)
        translator.reportSimulator(EventName.Delete, EventType.Ended, self.simulator)
      case .Install(let application):
        translator.reportSimulator(EventName.Install, EventType.Started, application)
        try simulator.interact().installApplication(application).performInteraction()
        translator.reportSimulator(EventName.Install, EventType.Ended, application)
      case .Launch(let launch):
        translator.reportSimulator(EventName.Launch, EventType.Started, launch)
        if let appLaunch = launch as? FBApplicationLaunchConfiguration {
          try simulator.interact().launchApplication(appLaunch).performInteraction()
        }
        else if let agentLaunch = launch as? FBAgentLaunchConfiguration {
          try simulator.interact().launchAgent(agentLaunch).performInteraction()
        }
        translator.reportSimulator(EventName.Launch, EventType.Ended, launch)
      }
    } catch let error as NSError {
      return .Failure(error.description)
    } catch let error as JSONError {
      return .Failure(error.description)
    }
    return .Success
  }
}
