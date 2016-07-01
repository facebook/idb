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

struct iOSRunnerContext<A> {
  let value: A
  let configuration: Configuration
  let defaults: Defaults
  let format: FBiOSTargetFormat
  let reporter: EventReporter
  let simulatorControl: FBSimulatorControl

  func map<B>(f: A -> B) -> iOSRunnerContext<B> {
    return iOSRunnerContext<B>(
      value: f(self.value),
      configuration: self.configuration,
      defaults: self.defaults,
      format: self.format,
      reporter: self.reporter,
      simulatorControl: self.simulatorControl
    )
  }

  func replace<B>(v: B) -> iOSRunnerContext<B> {
    return iOSRunnerContext<B>(
      value: v,
      configuration: self.configuration,
      defaults: self.defaults,
      format: self.format,
      reporter: self.reporter,
      simulatorControl: self.simulatorControl
    )
  }

  func query(query: FBiOSTargetQuery) -> [FBiOSTarget] {
    let simulators: [FBiOSTarget] = self.simulatorControl.set.query(query)
    return simulators
  }
}

struct BaseCommandRunner : Runner {
  let reporter: EventReporter
  let command: Command

  func run() -> CommandResult {
    do {
      let defaults = try Defaults.create(self.command.configuration, logWriter: FileHandleWriter.stdOutWriter)
      let simulatorControl = try defaults.configuration.buildSimulatorControl()
      let format = self.command.format ?? defaults.format
      let reporter = self.reporter
      let context = iOSRunnerContext(
        value: command,
        configuration: command.configuration,
        defaults: defaults,
        format: format,
        reporter: reporter,
        simulatorControl: simulatorControl
      )
      return CommandRunner(context: context).run()
    } catch DefaultsError.UnreadableRCFile(let string) {
      return .Failure("Unreadable .rc file " + string)
    } catch let error as NSError {
      return .Failure(error.description)
    }
  }
}

struct HelpRunner : Runner {
  let reporter: EventReporter
  let help: Help

  func run() -> CommandResult {
    reporter.reportSimpleBridge(EventName.Help, EventType.Discrete, self.help.description as NSString)
    return self.help.userInitiated ? CommandResult.Success : CommandResult.Failure("")
  }
}

struct CommandRunner : Runner {
  let context: iOSRunnerContext<Command>

  func run() -> CommandResult {
    for action in self.context.value.actions {
      guard let query = self.context.value.query ?? self.context.defaults.queryForAction(action) else {
        return CommandResult.Failure("No Query Provided")
      }
      let context = self.context.replace((action, query))
      let runner = ActionRunner(context: context)
      let result = runner.run()
      if case .Failure = result {
        return result
      }
    }
    return .Success
  }
}

struct ActionRunner : Runner {
  let context: iOSRunnerContext<(Action, FBiOSTargetQuery)>

  func run() -> CommandResult {
    let action = self.context.value.0.appendEnvironment(NSProcessInfo.processInfo().environment)
    let query = self.context.value.1

    switch action {
    case .Listen(let server):
      let context = self.context.replace((server, query))
      return ServerRunner(context: context).run()
    case .Create(let configuration):
      let context = self.context.replace(configuration)
      return SimulatorCreationRunner(context: context).run()
    default:
      let targets = self.context.query(query)
      let runner = SequenceRunner(runners: targets.map { target in
        if let simulator = target as? FBSimulator {
          let context = self.context.replace((action, simulator))
          return SimulatorActionRunner(context: context)
        }
        return CommandResult.Failure("\(target) is not a recognizable iOS Target").asRunner()
      })
      return runner.run()
    }
  }
}

struct ServerRunner : Runner, CommandPerformer {
  let context: iOSRunnerContext<(Server, FBiOSTargetQuery)>

  func run() -> CommandResult {
    self.context.reporter.reportSimple(EventName.Listen, EventType.Started, self.context.value.0)
    let runner = RelayRunner(relay: SynchronousRelay(relay: self.baseRelay, reporter: self.context.reporter))
    let result = runner.run()
    self.context.reporter.reportSimple(EventName.Listen, EventType.Ended, self.context.value.0)
    return result
  }

  var baseRelay: Relay { get {
    switch self.context.value.0 {
    case .StdIO:
      let commandBuffer = LineBuffer(performer: self, reporter: self.context.reporter)
      return FileHandleRelay(commandBuffer: commandBuffer)
    case .Socket(let portNumber):
      let commandBuffer = LineBuffer(performer: self, reporter: self.context.reporter)
      return SocketRelay(portNumber: portNumber, commandBuffer: commandBuffer, localEventReporter: self.context.reporter, socketOutput: self.context.configuration.outputOptions)
    case .Http(let portNumber):
      let query = self.context.value.1 ?? self.context.defaults.queryForAction(Action.Listen(self.context.value.0))!
      let performer = ActionPerformer(commandPerformer: self, configuration: self.context.configuration, query: query, format: self.context.format)
      return HttpRelay(portNumber: portNumber, performer: performer)
    }
  }}

  func perform(command: Command, reporter: EventReporter) -> CommandResult {
    let context = iOSRunnerContext(
      value: command,
      configuration: self.context.configuration,
      defaults: self.context.defaults,
      format: self.context.format,
      reporter: reporter,
      simulatorControl: self.context.simulatorControl
    )
    return CommandRunner(context: context).run()
  }
}
