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
  func run(writer: Writer) -> ActionResult
}

private func buildEventReporter(writer: Writer, format: Format, simulator: FBSimulator) -> EventReporter {
  switch format {
  case .HumanReadable(let keywords):
    return HumanReadableEventReporter(simulator: simulator, writer: writer, keywords: keywords)
  case .JSON:
    return JSONEventReporter(simulator: simulator, writer: writer)
  }
}

extension Configuration {
  func buildSimulatorControl() throws -> FBSimulatorControl {
    let debugLogging = self.options.contains(Configuration.Options.DebugLogging)
    let logger = FBSimulatorLogger.aslLogger().writeToStderrr(true, withDebugLogging: debugLogging)
    return try FBSimulatorControl.withConfiguration(self.controlConfiguration, logger: logger)
  }
}

public extension Command {
  func runFromCLI() -> Int32 {
    let writer = FileHandleWriter.stdIOWriter
    switch BaseRunner(command: self).run(writer.success) {
    case .Success:
      return 0
    case .Failure(let string):
      writer.failure.write(string)
      return 1
    }
  }
}

private struct SequenceRunner : Runner {
  let runners: [Runner]

  func run(writer: Writer) -> ActionResult {
    var output = ActionResult.Success
    for runner in runners {
      output = output.append(runner.run(writer))
      switch output {
        case .Failure: return output
        default: continue
      }
    }
    return output
  }
}

private struct BaseRunner : Runner {
  let command: Command

  func run(writer: Writer) -> ActionResult {
    do {
      switch (self.command) {
      case .Help:
        writer.write(Command.getHelp())
        return .Success
      case .Interactive(let configuration, let port):
        let defaults = try Defaults.create(configuration, logWriter: FileHandleWriter.stdIOWriter.failure)
        let control = try defaults.configuration.buildSimulatorControl()
        return InteractiveRunner(control: control, defaults: defaults, portNumber: port).run(writer)
      case .Perform(let configuration, let action):
        let defaults = try Defaults.create(configuration, logWriter: FileHandleWriter.stdIOWriter.failure)
        let control = try defaults.configuration.buildSimulatorControl()
        return ActionRunner(control: control, defaults: defaults, action: action).run(writer)
      }
    } catch DefaultsError.UnreadableRCFile(let string) {
      return .Failure("Unreadable .rc file " + string)
    } catch let error as NSError {
      return .Failure(error.description)
    }
  }
}

private struct ActionRunner : Runner {
  let control: FBSimulatorControl
  let defaults: Defaults
  let action: Action

  func run(writer: Writer) -> ActionResult {
    switch self.action {
    case .Interact(let interactions, let query, let format):
      return InteractionRunner(control: control, defaults: defaults, interactions: interactions, query: query, format: format).run(writer)
    case .Create(let configuration, let format):
      return CreationRunner(control: control, simulatorConfiguration: configuration, format: format ?? self.defaults.format).run(writer)
    }
  }
}

class InteractiveRunner : Runner, RelayTransformer {
  let control: FBSimulatorControl
  let defaults: Defaults
  let portNumber: Int?

  init(control: FBSimulatorControl, defaults: Defaults, portNumber: Int?) {
    self.control = control
    self.portNumber = portNumber
    self.defaults = defaults
  }

  func run(writer: Writer) -> ActionResult {
    if let portNumber = self.portNumber {
      writer.write("Starting Socket server on \(portNumber)")
      SocketRelay(portNumber: portNumber, transformer: self).start()
      writer.write("Ending Socket Server")
    } else {
      writer.write("Starting local interactive mode, listening on stdin")
      StdIORelay(transformer: self).start()
      writer.write("Ending local interactive mode")
    }
    return .Success
  }

  func transform(input: String, writer: Writer) -> ActionResult {
    do {
      let arguments = Arguments.fromString(input)
      let (_, action) = try Action.parser().parse(arguments)
      let runner = ActionRunner(control: self.control, defaults: self.defaults, action: action)
      return runner.run(writer)
    } catch let error as ParseError {
      return .Failure("Error: \(error.description)")
    } catch let error as NSError {
      return .Failure(error.description)
    }
  }
}

struct InteractionRunner : Runner {
  let control: FBSimulatorControl
  let defaults: Defaults
  let interactions: [Interaction]
  let query: Query?
  let format: Format?

  func run(writer: Writer) -> ActionResult {
    do {
      let simulators = try Query.perform(self.control.simulatorPool, query: self.query, defaults: self.defaults)
      let format = self.format ?? defaults.format
      let runners: [Runner] = self.interactions.flatMap { interaction in
        return simulators.map { simulator in
          SimulatorRunner(simulator: simulator, interaction: interaction.appendEnvironment(NSProcessInfo.processInfo().environment), format: format)
        }
      }
      return SequenceRunner(runners: runners).run(writer)
    } catch let error as QueryError {
      return ActionResult.Failure(error.description)
    } catch {
      return ActionResult.Failure("Unknown Query Error")
    }
  }
}

struct CreationRunner : Runner {
  let control: FBSimulatorControl
  let simulatorConfiguration: FBSimulatorConfiguration
  let format: Format

  func run(writer: Writer) -> ActionResult {
    do {
      let options = FBSimulatorAllocationOptions.Create
      let simulator = try self.control.simulatorPool.allocateSimulatorWithConfiguration(simulatorConfiguration, options: options)
      let reporter = buildEventReporter(writer, format: self.format, simulator: simulator)
      defer {
        simulator.userEventSink = nil
      }
      reporter.report(EventName.Create, EventType.Ended, simulator)
      return ActionResult.Success
    } catch let error as NSError {
      return ActionResult.Failure("Failed to Create Simulator \(error.description)")
    }
  }
}

private struct SimulatorRunner : Runner {
  let simulator: FBSimulator
  let interaction: Interaction
  let format: Format

  func run(writer: Writer) -> ActionResult {
    do {
      let event = buildEventReporter(writer, format: self.format, simulator: self.simulator)
      defer {
        self.simulator.userEventSink = nil
      }

      switch self.interaction {
      case .List:
        event.simulatorEvent()
      case .Approve(let bundleIDs):
        event.report(EventName.Approve, EventType.Started, [bundleIDs] as NSArray)
        try simulator.interact().authorizeLocationSettings(bundleIDs).performInteraction()
        event.report(EventName.Approve, EventType.Ended, [bundleIDs] as NSArray)
      case .Boot(let maybeLaunchConfiguration):
        let launchConfiguration = maybeLaunchConfiguration ?? FBSimulatorLaunchConfiguration.defaultConfiguration()!
        event.report(EventName.Boot, EventType.Started, launchConfiguration)
        try simulator.interact().prepareForLaunch(launchConfiguration).bootSimulator(launchConfiguration).performInteraction()
        event.report(EventName.Boot, EventType.Ended, launchConfiguration)
      case .Shutdown:
        event.report(EventName.Shutdown, EventType.Started, self.simulator)
        try simulator.interact().shutdownSimulator().performInteraction()
        event.report(EventName.Shutdown, EventType.Ended, self.simulator)
      case .Diagnose:
        let logs = simulator.logs.allLogs() as! [FBSimulatorLogs]
        event.report(EventName.Diagnostic, EventType.Discrete, logs)
      case .Delete:
        event.report(EventName.Delete, EventType.Started, self.simulator)
        try simulator.pool!.deleteSimulator(simulator)
        event.report(EventName.Delete, EventType.Ended, self.simulator)
      case .Install(let application):
        event.report(EventName.Delete, EventType.Started, application)
        try simulator.interact().installApplication(application).performInteraction()
        event.report(EventName.Delete, EventType.Started, application)
      case .Launch(let launch):
        event.report(EventName.Launch, EventType.Started, launch)
        if let appLaunch = launch as? FBApplicationLaunchConfiguration {
          try simulator.interact().launchApplication(appLaunch).performInteraction()
        }
        else if let agentLaunch = launch as? FBAgentLaunchConfiguration {
          try simulator.interact().launchAgent(agentLaunch).performInteraction()
        }
        event.report(EventName.Launch, EventType.Ended, launch)
      }
    } catch let error as NSError {
      return .Failure(error.description)
    } catch let error as JSON.Error {
      return .Failure(error.description)
    }
    return .Success
  }
}
