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

public extension Command {
  public static func fromArguments(arguments: [String]) -> Command {
    do {
      let (_, command) = try Command.parser().parse(arguments)
      return command
    } catch {
      return Command(configuration: Configuration.defaultConfiguration(), subcommand: .Help(nil))
    }
  }
}

enum ParseError : ErrorType {
  case EndOfInput
  case DoesNotMatch(String, String)
  case InvalidNumber

  private static func DoesNotMatchAnyOf(matches: [String]) -> ParseError {
    let inner = (matches as NSArray).componentsJoinedByString(", ")
    return .DoesNotMatch("any of", "[\(inner)]")
  }
}

/**
 Protocol for parsing a list of tokens.
 */
struct Parser<A> {
  let output: [String] throws -> ([String], A)

  func parse(tokens: [String]) throws -> ([String], A) {
    let (nextTokens, value) = try output(tokens)
    return (nextTokens, value)
  }
}

/**
  Primitives
*/
private extension Parser {
  func fmap<B>(f: A -> B) -> Parser<B> {
    return Parser<B>() { input in
      let (tokensOut, a) = try self.output(input)
      return (tokensOut, f(a))
    }
  }

  func bind<B>(f: A -> Parser<B>) -> Parser<B> {
    return Parser<B> { tokens in
      let (tokensA, valueA) = try self.parse(tokens)
      let (tokensB, valueB) = try f(valueA).parse(tokensA)
      return (tokensB, valueB)
    }
  }

  func optional() -> Parser<A?> {
    return Parser<A?> { tokens in
      do {
        let (nextTokens, value) = try self.parse(tokens)
        return (nextTokens, Optional.Some(value))
      } catch {
        return (tokens, nil)
      }
    }
  }

  func sequence<B>(p: Parser<B>) -> Parser<B> {
    return self.bind { _ in p }
  }
}

/**
  Derivatives
*/
private extension Parser {
  func handle(f: () -> A) -> Parser<A> {
    return self
      .optional()
      .fmap { optionalValue in
        guard let value = optionalValue else {
          return f()
        }
        return value
      }
  }

  func fallback(a: A) -> Parser<A> {
    return self.handle { _ in a }
  }

  static func fail(error: ParseError) -> Parser<A> {
    return Parser<A> { _ in
      throw error
    }
  }

  static func single(f: String throws -> A) -> Parser<A> {
    return Parser<A>() { tokens in
      guard let actual = tokens.first else {
        throw ParseError.EndOfInput
      }
      return try (Array(tokens.dropFirst(1)), f(actual))
    }
  }

  static func ofString(string: String, constant: A) -> Parser<A> {
    return Parser.single { token in
      if token != string {
        throw ParseError.DoesNotMatch(token, string)
      }
      return constant
    }
  }

  static func ofInt() -> Parser<Int> {
    return Parser<Int>.single { token in
      guard let integer = NSNumberFormatter().numberFromString(token)?.integerValue else {
        throw ParseError.InvalidNumber
      }
      return integer
    }
  }

  static func ofTwo<B>(a: Parser<A>, b: Parser<B>) -> Parser<(A, B)> {
    return a.bind { valueA in
      return b.fmap { valueB in
        return (valueA, valueB)
      }
    }
  }

  static func ofMany(parsers: [Parser<A>]) -> Parser<[A]> {
    return self.ofManyCount(parsers, count: 0)
  }

  static func ofAny(parsers: [Parser<A>]) -> Parser<A> {
    return self.ofManyCount(parsers, count: 1)
      .fmap { $0.first! }
  }

  static func succeeded(token: String, by: Parser<A>) -> Parser<A> {
    return Parser<()>
      .ofString(token, constant: ())
      .sequence(by)
  }

  private static func ofManyCount(parsers: [Parser<A>], count: Int) -> Parser<[A]> {
    assert(count >= 0, "Count should be >= 0")
    return Parser<[A]>() { tokens in
      var success = true
      var values: [A] = []
      var runningArgs = tokens
      var successes = 0

      while (success && !runningArgs.isEmpty) {
        success = false
        for parser in parsers {
          do {
            let output = try parser.parse(runningArgs)
            success = true
            successes++
            runningArgs = output.0
            values.append(output.1)
          } catch {}
        }
      }

      if (successes < count) {
        throw ParseError.EndOfInput
      }
      return (runningArgs, values)
    }
  }
}

protocol Parsable {
  static func parser() -> Parser<Self>
}

extension FBSimulatorState : Parsable {
  static func parser() -> Parser<FBSimulatorState> {
    return Parser<FBSimulatorState>.single { token in
      let state = FBSimulator.simulatorStateFromStateString(token)
      switch (state) {
      case .Unknown:
        throw ParseError.DoesNotMatchAnyOf([
          FBSimulatorState.Creating.description,
          FBSimulatorState.Shutdown.description,
          FBSimulatorState.Booting.description,
          FBSimulatorState.Booted.description,
          FBSimulatorState.ShuttingDown.description
        ])
      default:
        return state
      }
    }
  }
}

extension Command : Parsable {
  static func parser() -> Parser<Command> {
    return Parser
      .ofTwo(Configuration.parser(), b: Subcommand.parser())
      .fmap { (configuration, subcommand) in
        Command(configuration: configuration, subcommand: subcommand)
      }
  }
}

extension Configuration : Parsable {
  static func parser() -> Parser<Configuration> {
    return Parser
      .succeeded("--device-set", by: Parser.single { Configuration(deviceSetPath: $0) } )
      .fallback(Configuration.defaultConfiguration())
  }
}

extension Subcommand : Parsable {
  static func parser() -> Parser<Subcommand> {
    return Parser.ofAny([
      self.helpParser(),
      self.interactParser(),
      self.listParser(),
      self.bootParser(),
      self.shutdownParser(),
      self.diagnoseParser(),
    ])
  }

  static func helpParser() -> Parser<Subcommand> {
    return Parser.ofString("help", constant: .Help(nil))
  }

  static func interactParser() -> Parser<Subcommand> {
    return Parser
      .succeeded("interact", by: Parser.succeeded("--port", by: Parser<Int>.ofInt()).optional())
      .fmap { Subcommand.Interact($0) }
  }

  static func listParser() -> Parser<Subcommand> {
    let followingParser = Parser
      .ofTwo(Query.parser(), b: Format.parser())
      .fmap { (query, format) in
        Subcommand.List(query, format)
      }

    return Parser.succeeded("list", by: followingParser)
  }

  static func bootParser() -> Parser<Subcommand> {
    return Parser
      .succeeded("boot", by: Query.parser())
      .fmap { Subcommand.Boot($0) }
  }

  static func shutdownParser() -> Parser<Subcommand> {
    return Parser
      .succeeded("shutdown", by: Query.parser())
      .fmap { Subcommand.Shutdown($0) }
  }

  static func diagnoseParser() -> Parser<Subcommand> {
    return Parser
      .succeeded("diagnose", by: Query.parser())
      .fmap { Subcommand.Diagnose($0) }
  }
}

extension Query : Parsable {
  static func parser() -> Parser<Query> {
    return Parser
      .ofAny([
        Parser.ofString("creating", constant: Query.State(FBSimulatorState.Creating)),
        Parser.ofString("shutdown", constant: Query.State(FBSimulatorState.Shutdown)),
        Parser.ofString("booting", constant: Query.State(FBSimulatorState.Booting)),
        Parser.ofString("booted", constant: Query.State(FBSimulatorState.Booted)),
        Parser.ofString("shutting-down", constant: Query.State(FBSimulatorState.Booted)),
        Query.udidParser(),
        Query.nameParser()
      ])
  }

  private static func udidParser() -> Parser<Query> {
    return Parser.single { token in
      guard let _ = NSUUID(UUIDString: token) else {
        throw ParseError.InvalidNumber
      }
      return Query.UDID(token)
    }
  }

  private static func nameParser() -> Parser<Query> {
    return Parser.single { token in
      let mapping = FBSimulatorConfiguration.configurationsToAvailableDeviceTypes() as! [FBSimulatorConfiguration : AnyObject]
      let deviceNames = Set(mapping.keys.map { $0.deviceName })
      if (!deviceNames.contains(token)) {
        throw ParseError.InvalidNumber
      }
      let configuration: FBSimulatorConfiguration! = FBSimulatorConfiguration.named(token)
      return Query.Configured(configuration)
    }
  }
}

extension Format : Parsable {
  static func parser() -> Parser<Format> {
    return Parser
      .ofMany([
        Parser.ofString("--udid", constant: Format.UDID),
        Parser.ofString("--name", constant: Format.Name),
        Parser.ofString("--device-name", constant: Format.Name),
        Parser.ofString("--os-constant: version", constant: Format.Name)
      ])
      .fmap { formats in
        if (formats.isEmpty) {
          return Format.Compound([Format.Name, Format.UDID])
        }
        return Format.Compound(formats)
      }
  }
}
