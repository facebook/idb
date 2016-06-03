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

extension Configuration {
  func buildSimulatorControl() throws -> FBSimulatorControl {
    let controlConfiguration = FBSimulatorControlConfiguration(deviceSetPath: self.deviceSetPath, options: self.managementOptions)
    let logger = FBControlCoreGlobalConfiguration.defaultLogger()
    return try FBSimulatorControl.withConfiguration(controlConfiguration, logger: logger)
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
  let query: FBiOSTargetQuery?

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
      return SimulatorCreationRunner(
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
      let simulators = control.set.query(query)
      if simulators.count == 0 {
        reporter.reportSimpleBridge(EventName.Query, EventType.Discrete, "No Matching Devices in Set")
        return CommandResult.Success
      }
      let runners: [Runner] = simulators.map { simulator in
        SimulatorActionRunner(
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
  let query: FBiOSTargetQuery?
  let serverConfiguration: Server

  func run() -> CommandResult {
    reporter.reportSimple(EventName.Listen, EventType.Started, serverConfiguration)
    let runner = RelayRunner(relay: SynchronousRelay(relay: self.baseRelay, reporter: reporter))
    let result = runner.run()
    reporter.reportSimple(EventName.Listen, EventType.Ended, serverConfiguration)
    return result
  }

  var baseRelay: Relay { get {
    switch self.serverConfiguration {
    case .StdIO:
      let commandBuffer = LineBuffer(performer: self, reporter: self.reporter)
      return FileHandleRelay(commandBuffer: commandBuffer)
    case .Socket(let portNumber):
      let commandBuffer = LineBuffer(performer: self, reporter: self.reporter)
      return SocketRelay(portNumber: portNumber, commandBuffer: commandBuffer, localEventReporter: self.reporter, socketOutput: configuration.outputOptions)
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
