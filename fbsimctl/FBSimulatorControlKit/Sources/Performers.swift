/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

/**
 A Protocol for performing an Command producing an CommandResult.
 */
protocol CommandPerformer {
  func perform(command: Command, reporter: EventReporter) -> CommandResult
}

/**
 Forwards to a CommandPerformer based on Constructor Arguments
 */
struct ActionPerformer {
  let commandPerformer: CommandPerformer
  let configuration: Configuration
  let query: Query?
  let format: Format?

  func perform(action: Action, reporter: EventReporter) -> CommandResult {
    let command = Command.Perform(self.configuration, [action], self.query, self.format)
    return self.commandPerformer.perform(command, reporter: reporter)
  }
}

extension CommandPerformer {
  func perform(input: String, reporter: EventReporter) -> CommandResult {
    do {
      let arguments = Arguments.fromString(input)
      let (_, command) = try Command.parser.parse(arguments)
      return self.perform(command, reporter: reporter)
    } catch let error as ParseError {
      return .Failure("Error: \(error.description)")
    } catch let error as NSError {
      return .Failure(error.description)
    }
  }
}

/**
 Enum for defining the result of a translation.
 */
public enum CommandResult {
  case Success
  case Failure(String)

  func append(second: CommandResult) -> CommandResult {
    switch (self, second) {
    case (.Success, .Success):
      return .Success
    case (.Success, .Failure(let secondString)):
      return .Failure(secondString)
    case (.Failure(let firstString), .Success):
      return .Failure(firstString)
    case (.Failure(let firstString), .Failure(let secondString)):
      return .Failure("\(firstString)\n\(secondString)")
    }
  }
}

extension CommandResult : CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    get {
      switch self {
      case .Success: return "Success"
      case .Failure(let string): return "Failure '\(string)'"
      }
    }
  }

  public var debugDescription: String {
    get {
      return self.description
    }
  }
}

protocol SimulatorControlActionPerformer {
  func perform() -> CommandResult
}

struct SimulatorAction : SimulatorControlActionPerformer {
  let translator: EventSinkTranslator
  let name: EventName
  let subject: SimulatorControlSubject
  let action: Void throws -> Void

  func perform() -> CommandResult {
    do {
      self.translator.reportSimulator(self.name, EventType.Started, self.subject)
      try self.action()
      self.translator.reportSimulator(self.name, EventType.Ended, self.subject)
    } catch let error as NSError {
      return .Failure(error.description)
    } catch let error as JSONError {
      return .Failure(error.description)
    }
    return .Success
  }
}

struct SimulatorInteraction : SimulatorControlActionPerformer {
  let translator: EventSinkTranslator
  let name: EventName
  let subject: SimulatorControlSubject
  let interaction: FBSimulatorInteraction throws -> Void

  func perform() -> CommandResult {
    let simulator = self.translator.simulator
    let interaction = self.interaction
    let action = SimulatorAction(translator: self.translator, name: self.name, subject: self.subject) {
      let interact = simulator.interact
      try interaction(interact)
      try interact.perform()
    }
    return action.perform()
  }
}

struct DiagnosticsInteraction : SimulatorControlActionPerformer {
  let translator: EventSinkTranslator
  let subject: SimulatorControlSubject
  let query: FBSimulatorDiagnosticQuery
  let format: DiagnosticFormat

  func perform() -> CommandResult {
    let diagnostics = self.fetchDiagnostics()

    translator.reportSimulator(EventName.Diagnose, EventType.Started, query)
    for diagnostic in diagnostics {
      translator.reportSimulator(EventName.Diagnostic, EventType.Discrete, diagnostic)
    }
    translator.reportSimulator(EventName.Diagnose, EventType.Ended, query)
    return .Success
  }

  func fetchDiagnostics() -> [FBDiagnostic] {
    let diagnostics = self.translator.simulator.diagnostics
    let format = self.format

    return query.perform(diagnostics).map { diagnostic in
      switch format {
      case .CurrentFormat:
        return diagnostic
      case .Content:
        return FBDiagnosticBuilder(diagnostic: diagnostic).readIntoMemory().build()
      case .Path:
        return FBDiagnosticBuilder(diagnostic: diagnostic).writeOutToFile().build()
      }
    }
  }
}

struct SearchInteraction : SimulatorControlActionPerformer {
  let translator: EventSinkTranslator
  let search: FBBatchLogSearch

  func perform() -> CommandResult {
    let simulator = self.translator.simulator
    let diagnostics = simulator.diagnostics.allDiagnostics()
    let results = search.search(diagnostics)
    translator.reportSimulator(EventName.Search, EventType.Discrete, results)
    return .Success
  }
}

struct UploadInteraction : SimulatorControlActionPerformer {
  let translator: EventSinkTranslator
  let diagnostics: [FBDiagnostic]

  func perform() -> CommandResult {
    let diagnosticLocations: [(FBDiagnostic, String)] = diagnostics.map { diagnostic in
      return (diagnostic, diagnostic.asPath)
    }
    let mediaPredicate = NSPredicate.predicateForMediaPaths()
    let media = diagnosticLocations.filter { mediaPredicate.evaluateWithObject($0.1) }

    if media.count > 0 {
      let paths = media.map { $0.1 }
      let interaction = SimulatorInteraction(translator: translator, name: EventName.Upload, subject: paths as NSArray) { interaction in
        interaction.uploadMedia(paths)
      }
      let result = interaction.perform()
      switch result {
      case .Failure: return result
      default: break
      }
    }

    guard let basePath: NSString = translator.simulator.auxillaryDirectory else {
        return CommandResult.Failure("Could not determine aux directory for simulator \(self.translator.simulator) to path")
    }
    let arbitraryPredicate = NSCompoundPredicate(notPredicateWithSubpredicate: mediaPredicate)
    let arbitrary = diagnosticLocations.filter{ arbitraryPredicate.evaluateWithObject($0.1) }
    for (sourceDiagnostic, sourcePath) in arbitrary {
      guard let destinationPath = try? sourceDiagnostic.writeOutToDirectory(basePath as String) else {
        return CommandResult.Failure("Could not write out diagnostic \(sourcePath) to path")
      }
      let destinationDiagnostic = FBDiagnosticBuilder().updatePath(destinationPath).build()
      self.translator.reportSimulator(EventName.Upload, EventType.Discrete, destinationDiagnostic)
    }

    return CommandResult.Success
  }
}
