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
      case .Interact(let configuration, let port):
        let defaults = try Defaults.from(configuration.controlConfiguration.deviceSetPath, logWriter: FileHandleWriter.stdIOWriter.failure)
        let control = try configuration.buildSimulatorControl()
        return InteractiveRunner(control: control, defaults: defaults, portNumber: port).run(writer)
      case .Perform(let configuration, let action):
        let defaults = try Defaults.from(configuration.controlConfiguration.deviceSetPath, logWriter: FileHandleWriter.stdIOWriter.failure)
        let control = try configuration.buildSimulatorControl()
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
    do {
      let simulators = try Query.perform(self.control.simulatorPool, query: action.query)
      let format = self.action.format ?? defaults.format
      let runners: [Runner] = self.action.interactions.flatMap { interaction in
        simulators.map { simulator in
          SimulatorRunner(simulator: simulator, interaction: interaction, format: format)
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

private struct SimulatorRunner : Runner {
  let simulator: FBSimulator
  let interaction: Interaction
  let format: Format

  func run(writer: Writer) -> ActionResult {
    do {
      switch self.interaction {
      case .List:
        writer.write(self.formattedSimulator)
      case .Boot:
        writer.write("Booting \(self.formattedSimulator)")
        try simulator.interact().bootSimulator().performInteraction()
        writer.write("Booted \(self.formattedSimulator)")
      case .Shutdown:
        writer.write("Shutting Down \(self.formattedSimulator)")
        try simulator.interact().shutdownSimulator().performInteraction()
        writer.write("Shutdown \(self.formattedSimulator)")
      case .Diagnose:
        let logs: [NSDictionary] = simulator.logs.allLogs().flatMap { candidate in
          guard let log = candidate as? FBWritableLog else {
            return nil
          }
          return log.asDictionary
        }
        let string = try JSON.serializeToString(logs)
        writer.write(string)
      case .Install(let application):
        writer.write("Installing \(application.path) on \(self.formattedSimulator)")
        try simulator.interact().installApplication(application).performInteraction()
        writer.write("Installed \(application.path) on \(self.formattedSimulator)")
      case .Launch(let launch):
        writer.write("Launching \(launch.shortDescription()) on \(self.formattedSimulator)")
        if let appLaunch = launch as? FBApplicationLaunchConfiguration {
          try simulator.interact().launchApplication(appLaunch).performInteraction()
        }
        else if let agentLaunch = launch as? FBAgentLaunchConfiguration {
          try simulator.interact().launchAgent(agentLaunch).performInteraction()
        }
        writer.write("Launched \(launch.shortDescription()) on \(self.formattedSimulator)")
      }
    } catch let error as NSError {
      return .Failure(error.description)
    } catch is JSONError {
      return .Failure("Failed to encode to JSON")
    }
    return .Success
  }

  private var formattedSimulator: String {
    get {
      return Format.format(self.format, simulator: self.simulator)
    }
  }
}

extension Format {
  static func format(format: Format, simulator: FBSimulator) -> String {
    switch (format) {
    case .UDID:
      return simulator.udid
    case .Name:
      return simulator.name
    case .DeviceName:
      guard let configuration = simulator.configuration else {
        return "unknown-name"
      }
      return configuration.deviceName
    case .OSVersion:
      guard let configuration = simulator.configuration else {
        return "unknown-os"
      }
      return configuration.osVersionString
    case .State:
      return simulator.stateString
    case .ProcessIdentifier:
      guard let process = simulator.launchdSimProcess else {
        return "no-process"
      }
      return process.processIdentifier.description
    case .Compound(let subformats):
      let tokens: NSArray = subformats.map { Format.format($0, simulator: simulator)  }
      return tokens.componentsJoinedByString(" ")
    }
  }
}
