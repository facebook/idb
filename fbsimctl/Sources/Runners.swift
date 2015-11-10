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

extension Command {
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

    let controlConfiguration = FBSimulatorControlConfiguration(
      simulatorApplication: try! FBSimulatorApplication(error: ()),
      deviceSetPath: nil,
      options: .KillSpuriousSimulatorsOnFirstStart
    )
    let control = FBSimulatorControl.sharedInstanceWithConfiguration(controlConfiguration)
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
      return self.runSessionWithQuery(query) { session in
        try session.interact().bootSimulator().performInteraction()
        return "Booted \(session.simulator.udid)"
      }
    case .Shutdown:
      return .Failure("unimplemented")
    case .Diagnose(let query):
      return self.runSessionWithQuery(query) { session in
        if let sysLog = session.simulator.logs.systemLog() {
          return "\(sysLog.shortName) \(sysLog.asPath)"
        }
        return ""
      }
    default:
      return .Failure("unimplemented")
    }
  }

  private func runSessionWithQuery(query: Query, with: FBSimulatorSession throws -> String) -> Output {
    do {
      var buffer = ""
      let simulators = Query.perform(self.control.simulatorPool, query: query)
      for simulator in simulators {
        let session = FBSimulatorSession(simulator: simulator)
        let result = try with(session)
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
      let (_, command) = try Command.parser().parse(arguments)
      let runner = SubcommandRunner(subcommand: command.subcommand, control: self.control)
      return runner.run()
    } catch {
      return .Failure("NOPE")
    }
  }
}

private extension Query {
  static func perform(pool: FBSimulatorPool, query: Query) -> [FBSimulator] {
    return pool.allSimulators.filteredOrderedSetUsingPredicate(query.get(pool)).array as! [FBSimulator]
  }

  func get(pool: FBSimulatorPool) -> NSPredicate {
    switch (self) {
    case .UDID(let udid):
      return FBSimulatorPredicates.onlyUDID(udid)
    case .State(let state):
      return FBSimulatorPredicates.withState(state)
    case .Configured(let configuration):
      return FBSimulatorPredicates.matchingConfiguration(configuration)
    case .Compound(let subqueries):
      let predicates = subqueries.map {$0.get(pool)}
      return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
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
