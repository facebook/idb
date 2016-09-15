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
import FBDeviceControl

extension Configuration {
  func buildSimulatorControl() throws -> FBSimulatorControl {
    let logger = FBControlCoreGlobalConfiguration.defaultLogger()
    try FBSimulatorControlFrameworkLoader.loadPrivateFrameworks(logger)
    let controlConfiguration = FBSimulatorControlConfiguration(deviceSetPath: self.deviceSetPath, options: self.managementOptions)
    return try FBSimulatorControl.withConfiguration(controlConfiguration, logger: logger)
  }

  func buildDeviceControl() throws -> FBDeviceSet? {
    if case .Some = self.deviceSetPath {
      return nil
    }
    let logger = FBControlCoreGlobalConfiguration.defaultLogger()
    try FBDeviceControlFrameworkLoader.loadEssentialFrameworks(logger)
    return try FBDeviceSet.defaultSetWithLogger(logger)
  }
}

struct iOSRunnerContext<A> {
  let value: A
  let configuration: Configuration
  let defaults: Defaults
  let format: FBiOSTargetFormat
  let reporter: EventReporter
  let simulatorControl: FBSimulatorControl
  let deviceControl: FBDeviceSet?

  func map<B>(f: A -> B) -> iOSRunnerContext<B> {
    return iOSRunnerContext<B>(
      value: f(self.value),
      configuration: self.configuration,
      defaults: self.defaults,
      format: self.format,
      reporter: self.reporter,
      simulatorControl: self.simulatorControl,
      deviceControl: self.deviceControl
    )
  }

  func replace<B>(v: B) -> iOSRunnerContext<B> {
    return iOSRunnerContext<B>(
      value: v,
      configuration: self.configuration,
      defaults: self.defaults,
      format: self.format,
      reporter: self.reporter,
      simulatorControl: self.simulatorControl,
      deviceControl: self.deviceControl
    )
  }

  func query(query: FBiOSTargetQuery) -> [FBiOSTarget] {
    let devices: [FBiOSTarget] = self.deviceControl?.query(query) ?? []
    let simulators: [FBiOSTarget] = self.simulatorControl.set.query(query)
    let targets = devices + simulators
    return targets.sort { left, right in
      return FBiOSTargetComparison(left, right) == NSComparisonResult.OrderedDescending
    }
  }
}

struct BaseCommandRunner : Runner {
  let reporter: EventReporter
  let command: Command

  func run() -> CommandResult {
    do {
      let defaults = try Defaults.create(self.command.configuration, logWriter: FileHandleWriter.stdOutWriter)
      let simulatorControl = try defaults.configuration.buildSimulatorControl()
      let deviceControl = try defaults.configuration.buildDeviceControl()
      let format = self.command.format ?? defaults.format
      let reporter = self.reporter
      let context = iOSRunnerContext(
        value: command,
        configuration: command.configuration,
        defaults: defaults,
        format: format,
        reporter: reporter,
        simulatorControl: simulatorControl,
        deviceControl: deviceControl
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
    return self.help.userInitiated ? .Success(nil) : .Failure("")
  }
}

struct CommandRunner : Runner {
  let context: iOSRunnerContext<Command>

  func run() -> CommandResult {
    var result = CommandResult.Success(nil)
    for action in self.context.value.actions {
      guard let query = self.context.value.query ?? self.context.defaults.queryForAction(action) else {
        return CommandResult.Failure("No Query Provided")
      }
      let context = self.context.replace((action, query))
      let runner = ActionRunner(context: context)
      result = result.append(runner.run())
      if case .Failure = result {
        return result
      }
    }
    return result
  }
}

struct ActionRunner : Runner {
  let context: iOSRunnerContext<(Action, FBiOSTargetQuery)>

  func run() -> CommandResult {
    let action = self.context.value.0.appendEnvironment(NSProcessInfo.processInfo().environment)
    let query = self.context.value.1

    switch action {
    case .ListDeviceSets:
      let context = self.context.replace(FBSimulatorProcessFetcher(processFetcher: FBProcessFetcher()))
      return ListDeviceSetsRunner(context: context).run()
    case .Listen(let server):
      let context = self.context.replace((server, query))
      return ServerRunner(context: context).run()
    case .Create(let configuration):
      let context = self.context.replace(configuration)
      return SimulatorCreationRunner(context: context).run()
    default:
      let action = action.appendEnvironment(NSProcessInfo.processInfo().environment)
      let targets = self.context.query(query)
      let runner = SequenceRunner(runners: targets.map { target in
        if let simulator = target as? FBSimulator {
          let context = self.context.replace((action, simulator))
          return SimulatorActionRunner(context: context)
        }
        if let device = target as? FBDevice {
          let context = self.context.replace((action, device))
          return DeviceActionRunner(context: context)
        }
        return CommandResult.Failure("Unrecognizable Target \(target)").asRunner()
      })
      return runner.run()
    }
  }
}

struct ServerRunner : Runner, CommandPerformer {
  let context: iOSRunnerContext<(Server, FBiOSTargetQuery)>

  func run() -> CommandResult {
    let relay = SynchronousRelay(relay: self.baseRelay, reporter: self.context.reporter) {
      self.context.reporter.reportSimple(EventName.Listen, EventType.Started, self.context.value.0)
    }
    let result = RelayRunner(relay: relay).run()
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
      simulatorControl: self.context.simulatorControl,
      deviceControl: self.context.deviceControl
    )
    return CommandRunner(context: context).run()
  }
}

struct ListDeviceSetsRunner : Runner {
  let context: iOSRunnerContext<FBSimulatorProcessFetcher>

  func run() -> CommandResult {
    let launchdProcessesToDeviceSets = self.context.value.launchdProcessesToContainingDeviceSet()
    for deviceSet in Set(launchdProcessesToDeviceSets.values).sort() {
      self.context.reporter.reportSimple(EventName.ListDeviceSets, EventType.Discrete, deviceSet)
    }
    return CommandResult.Success(nil)
  }
}
