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
    let logger = FBControlCoreGlobalConfiguration.defaultLogger
    try FBSimulatorControlFrameworkLoader.loadPrivateFrameworks(logger)
    let controlConfiguration = FBSimulatorControlConfiguration(deviceSetPath: self.deviceSetPath, options: self.managementOptions)
    return try FBSimulatorControl.withConfiguration(controlConfiguration, logger: logger)
  }

  func buildDeviceControl() throws -> FBDeviceSet? {
    if case .some = self.deviceSetPath {
      return nil
    }
    let logger = FBControlCoreGlobalConfiguration.defaultLogger
    try FBDeviceControlFrameworkLoader.loadEssentialFrameworks(logger)
    return try FBDeviceSet.defaultSet(with: logger)
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

  func map<B>(_ f: (A) -> B) -> iOSRunnerContext<B> {
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

  func replace<B>(_ v: B) -> iOSRunnerContext<B> {
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

  func query(_ query: FBiOSTargetQuery) -> [FBiOSTarget] {
    let devices: [FBiOSTarget] = self.deviceControl?.query(query) ?? []
    let simulators: [FBiOSTarget] = self.simulatorControl.set.query(query)
    let targets = devices + simulators
    return targets.sorted { left, right in
      return FBiOSTargetComparison(left, right) == ComparisonResult.orderedDescending
    }
  }

  func querySingleSimulator(_ query: FBiOSTargetQuery) throws -> FBSimulator {
    let targets = self.query(query)
    if targets.count > 1 {
      throw QueryError.TooManyMatches(targets, 1)
    }
    guard let target = targets.first else {
      throw QueryError.NoMatches
    }
    guard let simulator = target as? FBSimulator else {
      let expected = FBiOSTargetTypeStringsFromTargetType(FBiOSTargetType.simulator).first!
      let actual = FBiOSTargetTypeStringsFromTargetType(target.targetType).first!
      throw QueryError.WrongTarget(expected, actual)
    }
    return simulator
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
    } catch DefaultsError.unreadableRCFile(let string) {
      return .failure("Unreadable .rc file " + string)
    } catch let error as NSError {
      return .failure(error.description)
    }
  }
}

struct HelpRunner : Runner {
  let reporter: EventReporter
  let help: Help

  func run() -> CommandResult {
    if let error = self.help.error {
      return .failure(error.description)
    }
    return .success(self.help.description)
  }
}

struct CommandRunner : Runner {
  let context: iOSRunnerContext<Command>

  func run() -> CommandResult {
    let command = self.context.value
    var result = CommandResult.success(nil)
    for action in command.actions {
      guard let query = self.context.value.query ?? self.context.defaults.queryForAction(action) else {
        return CommandResult.failure("No Query Provided")
      }
      let context = self.context.replace((action, query))
      let runner = ActionRunner(context: context)
      result = result.append(runner.run())
      if case .failure = result.outcome {
        return result
      }
    }
    // Some commands are asynchronous, therefore we need to add a listen
    if let listenHandle = CommandRunner.shouldAddListen(command: command, result: result) {
      let listenInterface = ListenInterface(stdin: false, http: nil, hid: nil, handle: listenHandle)
      let runner = ListenRunner(context: self.context.replace((listenInterface, FBiOSTargetQuery.allTargets())))
      let _ = runner.run()
    }
    return result
  }

  private static func shouldAddListen(command: Command, result: CommandResult) -> FBTerminationHandle? {
    guard let handle = result.handles.first else {
      return nil
    }
    for action in command.actions {
      if case .listen = action {
        return nil
      }
    }
    return handle
  }
}

struct ActionRunner : Runner {
  let context: iOSRunnerContext<(Action, FBiOSTargetQuery)>

  func run() -> CommandResult {
    let action = self.context.value.0.appendEnvironment(ProcessInfo.processInfo.environment)
    let query = self.context.value.1

    switch action {
    case .config:
      let config = FBControlCoreGlobalConfiguration()
      let subject = SimpleSubject(.config, .discrete, ControlCoreSubject(config))
      return CommandResult.success(subject)
    case .list:
      let context = self.context.replace(query)
      return ListRunner(context: context).run()
    case .listDeviceSets:
      let context = self.context.replace(self.context.simulatorControl.serviceContext)
      return ListDeviceSetsRunner(context: context).run()
    case .listen(let server):
      let context = self.context.replace((server, query))
      return ListenRunner(context: context).run()
    case .create(let configuration):
      let context = self.context.replace(configuration)
      return SimulatorCreationRunner(context: context).run()
    default:
      let action = action.appendEnvironment(ProcessInfo.processInfo.environment)
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
        return CommandResult.failure("Unrecognizable Target \(target)").asRunner()
      })
      return runner.run()
    }
  }
}

struct ListenRunner : Runner, ActionPerformer {
  let context: iOSRunnerContext<(ListenInterface, FBiOSTargetQuery)>
  let configuration: Configuration
  let query: FBiOSTargetQuery

  init(context: iOSRunnerContext<(ListenInterface, FBiOSTargetQuery)>) {
    self.context = context
    self.configuration = context.configuration
    self.query = context.value.1
  }

  func run() -> CommandResult {
    do {
      let (interface, baseRelay, reporter, awaitable) = try self.makeBaseRelay()
      let relay = SynchronousRelay(relay: baseRelay, reporter: reporter, awaitable: awaitable) {
        reporter.reportSimple(.listen, .started, interface)
      }
      let result = RelayRunner(relay: relay).run()
      reporter.reportSimple(.listen, .ended, interface)
      return result
    } catch let error as CustomStringConvertible {
      return CommandResult.failure(error.description)
    } catch {
      return CommandResult.failure("Unknown Error")
    }
  }

  func makeBaseRelay() throws -> (ListenInterface, Relay, EventReporter, FBTerminationAwaitable?) {
    let (interface, query) = self.context.value
    let reporter = self.context.reporter
    let interpreter = JSONEventInterpreter(pretty: false)
    var relays: [Relay] = []
    var awaitable: FBTerminationAwaitable? = nil

    if interface.isEmptyListen {
      awaitable = interface.handle as? FBTerminationAwaitable
    }
    if let httpPort = interface.http {
      relays.append(HttpRelay(portNumber: httpPort, performer: self))
    }
    if interface.stdin {
      let target = try self.context.querySingleSimulator(query)
      let bridge = ActionReaderDelegateBridge(interpreter: interpreter, reporter: reporter)
      let reader = FBiOSActionReader.fileReader(for: target, delegate: bridge, read: FileHandle.standardInput, write: FileHandle.standardOutput)
      awaitable = reader
      relays.append(reader)
    }
    if let hidPort = interface.hid {
      let target = try self.context.querySingleSimulator(query)
      let bridge = ActionReaderDelegateBridge(interpreter: interpreter, reporter: reporter)
      let reader = FBiOSActionReader.socketReader(for: target, delegate: bridge, port: hidPort)
      awaitable = reader
      relays.append(reader)
    }
    return (interface, CompositeRelay(relays: relays), reporter, awaitable)
  }

  func runnerContext(_ reporter: EventReporter) -> iOSRunnerContext<()> {
    return iOSRunnerContext(
      value: (),
      configuration: self.context.configuration,
      defaults: self.context.defaults,
      format: self.context.format,
      reporter: reporter,
      simulatorControl: self.context.simulatorControl,
      deviceControl: self.context.deviceControl
    )
  }

  func perform(reporter: EventReporter, action: Action, queryOverride: FBiOSTargetQuery?) -> CommandResult {
    let query = queryOverride ?? self.query
    let context = self.runnerContext(reporter).replace((action, query))
    return ActionRunner(context: context).run()
  }
}

struct ListRunner : Runner {
  let context: iOSRunnerContext<FBiOSTargetQuery>

  func run() -> CommandResult {
    let targets = self.context.query(self.context.value)
    let subjects: [EventReporterSubject] = targets.map { target in
      SimpleSubject(.list, .discrete, iOSTargetSubject(target: target, format: self.context.format))
    }
    return .success(CompositeSubject(subjects))
  }
}

struct ListDeviceSetsRunner : Runner {
  let context: iOSRunnerContext<FBSimulatorServiceContext>

  func run() -> CommandResult {
    let deviceSets = self.deviceSets
    let subjects: [EventReporterSubject] = deviceSets.map { deviceSet in
      SimpleSubject(.listDeviceSets, .discrete, deviceSet)
    }
    return .success(CompositeSubject(subjects))
  }

  fileprivate var deviceSets: [String] { get {
    let serviceContext = self.context.value
    return serviceContext.pathsOfAllDeviceSets().sorted()
  }}
}
