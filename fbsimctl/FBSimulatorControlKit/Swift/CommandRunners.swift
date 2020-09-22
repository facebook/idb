/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBDeviceControl
import FBSimulatorControl
import Foundation

extension Configuration {
  func buildSimulatorControl() throws -> FBSimulatorControl {
    let logger = FBControlCoreGlobalConfiguration.defaultLogger
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(logger)
    let controlConfiguration = FBSimulatorControlConfiguration(deviceSetPath: deviceSetPath, options: managementOptions, logger: logger, reporter: nil)
    return try FBSimulatorControl.withConfiguration(controlConfiguration)
  }

  func buildDeviceControl() throws -> FBDeviceSet? {
    if case .some = deviceSetPath {
      return nil
    }
    let logger = FBControlCoreGlobalConfiguration.defaultLogger
    try FBDeviceControlFrameworkLoader().loadPrivateFrameworks(logger)
    return try FBDeviceSet(logger: logger, delegate: nil, ecidFilter: nil)
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
      value: f(value),
      configuration: configuration,
      defaults: defaults,
      format: format,
      reporter: reporter,
      simulatorControl: simulatorControl,
      deviceControl: deviceControl
    )
  }

  func replace<B>(_ v: B) -> iOSRunnerContext<B> {
    return iOSRunnerContext<B>(
      value: v,
      configuration: configuration,
      defaults: defaults,
      format: format,
      reporter: reporter,
      simulatorControl: simulatorControl,
      deviceControl: deviceControl
    )
  }

  func query(_ query: FBiOSTargetQuery) -> [FBiOSTarget] {
    let devices: [FBiOSTarget] = deviceControl?.query(query) ?? []
    let simulators: [FBiOSTarget] = simulatorControl.set.query(query)
    let targets = devices + simulators
    return targets.sorted { left, right in
      FBiOSTargetComparison(left, right) == ComparisonResult.orderedDescending
    }
  }

  func querySingleTarget(_ query: FBiOSTargetQuery) throws -> FBiOSTarget {
    let targets = self.query(query)
    if targets.count > 1 {
      throw QueryError.TooManyMatches(targets, 1)
    }
    guard let target = targets.first else {
      throw QueryError.NoMatches
    }
    return target
  }
}

struct BaseCommandRunner: Runner {
  let reporter: EventReporter
  let command: Command

  func run() -> CommandResult {
    do {
      let defaults = try Defaults.create(command.configuration, logWriter: FBFileWriter.stdOutWriter)
      let simulatorControl = try defaults.configuration.buildSimulatorControl()
      let deviceControl = try defaults.configuration.buildDeviceControl()
      let format = command.format ?? defaults.format
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
    } catch let DefaultsError.unreadableRCFile(string) {
      return .failure("Unreadable .rc file " + string)
    } catch let error as NSError {
      return .failure(error.description)
    }
  }
}

struct HelpRunner: Runner {
  let reporter: EventReporter
  let help: Help

  func run() -> CommandResult {
    if let error = self.help.error {
      return .failure(error.description)
    }
    return .success(FBEventReporterSubject(string: help.description))
  }
}

struct CommandRunner: Runner {
  let context: iOSRunnerContext<Command>

  func run() -> CommandResult {
    let command = context.value
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
    if let continuation = CommandRunner.shouldAddListen(command: command, result: result) {
      let listenInterface = ListenInterface(stdin: false, http: nil, hid: nil, continuation: continuation)
      let runner = ListenRunner(context: context.replace((listenInterface, FBiOSTargetQuery.allTargets())))
      _ = runner.run()
    }
    return result
  }

  private static func shouldAddListen(command: Command, result: CommandResult) -> FBiOSTargetContinuation? {
    guard let continuation = result.continuations.first else {
      return nil
    }
    for action in command.actions {
      if case .listen = action {
        return nil
      }
    }
    if let completed = continuation.completed, completed.state != .running {
      return nil
    }
    return continuation
  }
}

struct ActionRunner: Runner {
  let context: iOSRunnerContext<(Action, FBiOSTargetQuery)>

  func run() -> CommandResult {
    let action = context.value.0.appendEnvironment(ProcessInfo.processInfo.environment)
    let query = context.value.1

    switch action {
    case .config:
      let config = FBControlCoreGlobalConfiguration()
      let subject = FBEventReporterSubject(name: .config, type: .discrete, subject: config.subject)
      return CommandResult.success(subject)
    case .list:
      let context = self.context.replace(query)
      return ListRunner(context: context).run()
    case .listDeviceSets:
      let context = self.context.replace(self.context.simulatorControl.serviceContext)
      return ListDeviceSetsRunner(context: context).run()
    case let .listen(server):
      let context = self.context.replace((server, query))
      return ListenRunner(context: context).run()
    case let .create(configuration):
      let context = self.context.replace(configuration)
      return SimulatorCreationRunner(context: context, eventName: .create, futures: context.createSimulators(configuration)).run()
    default:
      let action = action.appendEnvironment(ProcessInfo.processInfo.environment)
      let targets = context.query(query)
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

struct ListenRunner: Runner, ActionPerformer {
  let context: iOSRunnerContext<(ListenInterface, FBiOSTargetQuery)>
  let configuration: Configuration
  let query: FBiOSTargetQuery
  let workQueue: DispatchQueue

  init(context: iOSRunnerContext<(ListenInterface, FBiOSTargetQuery)>) {
    self.context = context
    configuration = context.configuration
    query = context.value.1
    workQueue = DispatchQueue(label: "com.facebook.fbsimctl.listen.executor")
  }

  func run() -> CommandResult {
    do {
      let (interface, baseRelay, reporter, continuation) = try makeBaseRelay()
      let relay = SynchronousRelay(relay: baseRelay, reporter: reporter, continuation: continuation) {
        reporter.reportSimple(.listen, .started, ListenSubject(interface))
      }
      let result = RelayRunner(relay: relay).run()
      reporter.reportSimple(.listen, .ended, ListenSubject(interface))
      return result
    } catch let error as CustomStringConvertible {
      return CommandResult.failure(error.description)
    } catch {
      return CommandResult.failure("Unknown Error")
    }
  }

  func makeBaseRelay() throws -> (ListenInterface, Relay, EventReporter, FBiOSTargetContinuation?) {
    let (interface, query) = context.value
    let reporter = context.reporter
    let interpreter = FBEventInterpreter.jsonEventInterpreter(false)
    var relays: [Relay] = []
    var continuation: FBiOSTargetContinuation?

    if interface.isEmptyListen {
      continuation = interface.continuation
    }
    if let httpPort = interface.http {
      relays.append(HttpRelay(portNumber: httpPort, performer: self))
    }
    if interface.stdin {
      let target = try context.querySingleTarget(query)
      let delegate = FBReportingiOSActionReaderDelegate(reporter: FBEventReporter.withInterpreter(interpreter, consumer: reporter.writer))
      let reader = FBiOSActionReader.fileReader(for: target, delegate: delegate, read: FileHandle.standardInput, write: FileHandle.standardOutput)
      continuation = reader
      relays.append(reader)
    }
    if let hidPort = interface.hid {
      let target = try context.querySingleTarget(query)
      let delegate = FBReportingiOSActionReaderDelegate(reporter: FBEventReporter.withInterpreter(interpreter, consumer: reporter.writer))
      let reader = FBiOSActionReader.socketReader(for: target, delegate: delegate, port: hidPort)
      continuation = reader
      relays.append(reader)
    }
    return (interface, CompositeRelay(relays: relays), reporter, continuation)
  }

  func runnerContext(_ reporter: EventReporter) -> iOSRunnerContext<()> {
    return iOSRunnerContext(
      value: (),
      configuration: context.configuration,
      defaults: context.defaults,
      format: context.format,
      reporter: reporter,
      simulatorControl: context.simulatorControl,
      deviceControl: context.deviceControl
    )
  }

  func future(reporter: EventReporter, action: Action, queryOverride: FBiOSTargetQuery?) -> FBFuture<CommandResultBox> {
    let query = queryOverride ?? self.query
    let context = runnerContext(reporter).replace((action, query))

    return FBFuture.onQueue(workQueue, resolve: {
      if case let .coreFuture(coreFuture) = action {
        let futures = context.query(query).map { target in
          coreFuture.run(with: target, consumer: reporter.writer, reporter: reporter)
        }
        return FBFuture(futures: futures).mapReplace(CommandResultBox(value: CommandResult.success(nil)))
      }
      let result = ActionRunner(context: context).run()
      return FBFuture(result: CommandResultBox(value: result))
    })
  }
}

struct ListRunner: Runner {
  let context: iOSRunnerContext<FBiOSTargetQuery>

  func run() -> CommandResult {
    let targets = context.query(context.value)
    let subjects: [EventReporterSubject] = targets.map { target in
      FBEventReporterSubject(name: .list, type: .discrete, subject: FBEventReporterSubject(target: target, format: self.context.format))
    }
    return .success(FBEventReporterSubject(subjects: subjects))
  }
}

struct ListDeviceSetsRunner: Runner {
  let context: iOSRunnerContext<FBSimulatorServiceContext>

  func run() -> CommandResult {
    let deviceSets = self.deviceSets
    let subjects: [EventReporterSubject] = deviceSets.map { deviceSet in
      FBEventReporterSubject(name: .listDeviceSets, type: .discrete, subject: FBEventReporterSubject(string: deviceSet))
    }
    return .success(FBEventReporterSubject(subjects: subjects))
  }

  fileprivate var deviceSets: [String] {
    let serviceContext = context.value
    return serviceContext.pathsOfAllDeviceSets().sorted()
  }
}
