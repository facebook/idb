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
  func run() -> Output
}

extension Configuration {
  func build() -> FBSimulatorControl {
    let logger = FBSimulatorLogger.aslLogger().writeToStderrr(true, withDebugLogging: self.debugLogging)
    return try! FBSimulatorControl.withConfiguration(self.controlConfiguration, logger: logger)
  }
}

public extension Command {
  func runFromCLI() -> Void {
    switch (BaseRunner(command: self).run()) {
    case .Failure(let string):
      print(string)
    case .Success(let string):
      print(string)
    }
  }
}

private struct SequenceRunner : Runner {
  let runners: [Runner]

  func run() -> Output {
    var output = Output.Success("")
    for runner in runners {
      output = output.append(runner.run())
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

  func run() -> Output {
    switch (self.command) {
    case .Help:
      return .Success(Command.getHelp())
    case .Interact(let configuration, let port):
      return InteractionRunner(control: configuration.build(), portNumber: port).run()
    case .Perform(let configuration, let actions):
      return SequenceRunner(runners: actions.map { ActionRunner(action: $0, control: configuration.build()) } ).run()
    }
  }
}


private struct ActionRunner : Runner {
  let action: Action
  let control: FBSimulatorControl

  // TODO: Sessions don't make much sense in this context, combine multiple simulators into one session
  func run() -> Output {
    switch (self.action) {
    case .List(let query, let format):
      let simulators = Query.perform(control.simulatorPool, query: query)
      return .Success(Format.formatAll(format)(simulators: simulators))
    case .Boot(let query):
      return self.runSimulatorWithQuery(query) { simulator in
        try simulator.interact().bootSimulator().performInteraction()
        return "Booted \(simulator.udid)"
      }
    case .Shutdown(let query):
      return self.runSimulatorWithQuery(query) { simulator in
        try simulator.interact().shutdownSimulator().performInteraction()
        return "Shutdown \(simulator.udid)"
      }
    case .Diagnose(let query):
      return self.runSimulatorWithQuery(query) { simulator in
        if let sysLog = simulator.logs.systemLog() {
          return "\(sysLog.shortName) \(sysLog.asPath)"
        }
        return ""
      }
    default:
      return .Failure("unimplemented")
    }
  }

  private func runSimulatorWithQuery(query: Query, _ transform: FBSimulator throws -> String) -> Output {
    return QueryRunner(query: query, control: self.control, transform: transform).run()
  }
}

private struct QueryRunner : Runner {
  let query: Query
  let control: FBSimulatorControl
  let transform: FBSimulator throws -> String

  func run() -> Output {
    let simulators = Query.perform(self.control.simulatorPool, query: query)
    return SequenceRunner(runners: simulators.map { SimulatorRunner(simulator: $0, transform: self.transform) } ).run()
  }

  struct SimulatorRunner : Runner {
    let simulator: FBSimulator
    let transform: FBSimulator throws -> String

    func run() -> Output {
      do {
        let result = try self.transform(self.simulator)
        return .Success(result)
      } catch let error as NSError {
        return .Failure(error.description)
      }
    }
  }
}

private class InteractionRunner : Runner, RelayTransformer {
  let control: FBSimulatorControl
  let portNumber: Int?

  init(control: FBSimulatorControl, portNumber: Int?) {
    self.control = control
    self.portNumber = portNumber
  }

  func run() -> Output {
    if let portNumber = self.portNumber {
      print("Starting Socket server on \(portNumber)")
      SocketRelay(portNumber: portNumber, transformer: self).start()
      return .Success("Ending Socket Server")
    }
    print("Starting local interactive mode")
    StdIORelay(transformer: self).start()
    return .Success("Ending local interactive mode")
  }

  func transform(input: String) -> Output {
    let arguments = input.componentsSeparatedByCharactersInSet(NSCharacterSet.whitespaceCharacterSet())
    do {
      let (_, action) = try Action.parser().parse(arguments)
      let runner = ActionRunner(action: action, control: self.control)
      return runner.run()
    } catch {
      return .Failure("NOPE")
    }
  }
}

private extension Query {
  static func perform(pool: FBSimulatorPool, query: Query) -> [FBSimulator] {
    let array: NSArray = pool.allSimulators
    return array.filteredArrayUsingPredicate(query.get(pool)) as! [FBSimulator]
  }

  func get(pool: FBSimulatorPool) -> NSPredicate {
    switch (self) {
    case .UDID(let udids):
      return FBSimulatorPredicates.udids(Array(udids))
    case .State(let states):
      return NSCompoundPredicate(
        orPredicateWithSubpredicates: states.map(FBSimulatorPredicates.state) as! [NSPredicate]
      )
    case .Configured(let configurations):
      return NSCompoundPredicate(
        orPredicateWithSubpredicates: configurations.map(FBSimulatorPredicates.configuration) as! [NSPredicate]
      )
    case .And(let subqueries):
      return NSCompoundPredicate(
        andPredicateWithSubpredicates: subqueries.map { $0.get(pool) }
      )
    }
  }
}

private extension Format {
  static func format(format: Format)(simulator: FBSimulator) -> String {
    switch (format) {
    case Format.UDID:
      return simulator.udid
    case Format.Name:
      return simulator.name
    case Format.DeviceName:
      return simulator.configuration.deviceName
    case Format.OSVersion:
      return simulator.configuration.osVersionString
    case Format.Compound(let subformats):
      let tokens: NSArray = subformats.map { Format.format($0)(simulator: simulator) }
      return tokens.componentsJoinedByString(" ")
    }
  }

  static func formatAll(format: Format)(simulators: [FBSimulator]) -> String {
    return simulators
      .map(Format.format(format))
      .joinWithSeparator("\n")
  }
}
