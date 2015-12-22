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

private struct BaseRunner : Runner {
  let command: Command

  func run() -> Output {
    switch (self.command.subcommand) {
    case .Help:
      return .Success(Command.getHelp())
    default:
      break
    }

    let control = try! FBSimulatorControl.withConfiguration(command.configuration)
    switch (self.command.subcommand) {
    case .Interact(let portNumber):
      return InteractionRunner(control: control, portNumber: portNumber).run()
    default:
      let runner = SubcommandRunner(subcommand: self.command.subcommand, control: control)
      return runner.run()
    }
  }
}

private struct SubcommandRunner : Runner {
  let subcommand: Subcommand
  let control: FBSimulatorControl

  // TODO: Sessions don't make much sense in this context, combine multiple simulators into one session
  func run() -> Output {
    switch (self.subcommand) {
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

  private func runSimulatorWithQuery(query: Query, with: FBSimulator throws -> String) -> Output {
    do {
      var buffer = ""
      let simulators = Query.perform(self.control.simulatorPool, query: query)
      for simulator in simulators {
        let result = try with(simulator)
        buffer.appendContentsOf(result)
        buffer.append("\n" as Character)
      }
      return .Success(buffer)
    } catch let error as NSError {
      return .Failure(error.description)
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
      let (_, subcommand) = try Subcommand.parser().parse(arguments)
      let runner = SubcommandRunner(subcommand: subcommand, control: self.control)
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
      return NSCompoundPredicate(
        orPredicateWithSubpredicates: udids.map(FBSimulatorPredicates.onlyUDID) as! [NSPredicate]
      )
    case .State(let states):
      return NSCompoundPredicate(
        orPredicateWithSubpredicates: states.map(FBSimulatorPredicates.withState) as! [NSPredicate]
      )
    case .Configured(let configurations):
      return NSCompoundPredicate(
        orPredicateWithSubpredicates: configurations.map(FBSimulatorPredicates.matchingConfiguration) as! [NSPredicate]
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
