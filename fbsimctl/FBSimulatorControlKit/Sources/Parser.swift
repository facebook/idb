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

public enum ParseError : Error, CustomStringConvertible {
  case endOfInput
  case doesNotMatch(String, String)
  case couldNotInterpret(String, String)
  case custom(String)

  public var description: String { get {
    switch self {
    case .endOfInput:
      return "End of Input"
    case .doesNotMatch(let expected, let actual):
      return "'\(actual)' does not match '\(expected)'"
    case .couldNotInterpret(let typeName, let actual):
      return "\(actual) could not be interpreted as \(typeName)"
    case .custom(let message):
      return message
    }
  }}
}

/**
 Protocol for parsing a list of tokens.
 */
public struct Parser<A> : CustomStringConvertible {
  let matchDescription: ParserDescription
  let output: ([String]) throws -> ([String], A)

  init(_ matchDescription: ParserDescription, output: @escaping ([String]) throws -> ([String], A)) {
    self.matchDescription = matchDescription
    self.output = output
  }

  public func parse(_ tokens: [String]) throws -> ([String], A) {
    let (nextTokens, value) = try output(tokens)
    return (nextTokens, value)
  }

  public var description: String {
    return self.matchDescription.normalised.usage
  }
}

/**
  Primitives
*/
extension Parser {
  func fmap<B>(_ f: @escaping (A) throws -> B) -> Parser<B> {
    return Parser<B>(self.matchDescription) { input in
      let (tokensOut, a) = try self.output(input)
      let b = try f(a)
      return (tokensOut, b)
    }
  }

  func bind<B>(_ f: @escaping (A) -> Parser<B>) -> Parser<B> {
    return Parser<B>(self.matchDescription) { tokens in
      let (tokensA, valueA) = try self.parse(tokens)
      let (tokensB, valueB) = try f(valueA).parse(tokensA)
      return (tokensB, valueB)
    }
  }

  func optional() -> Parser<A?> {
    return Parser<A?>(OptionalDesc(child: self.matchDescription)) { tokens in
      do {
        let (tokens, value) = try self.parse(tokens)
        return (tokens, Optional.some(value))
      } catch {
        return (tokens, nil)
      }
    }
  }

  func handle(_ f: @escaping (ParseError) -> A) -> Parser<A> {
    return Parser<A>(self.matchDescription) { tokens in
      do {
        return try self.parse(tokens)
      } catch let error as ParseError {
        return (tokens, f(error))
      }
    }
  }

  func sequence<B>(_ p: Parser<B>) -> Parser<B> {
    return self
      .bind({ _ in p })
      .describe(SequenceDesc(children: [
        self.matchDescription,
        p.matchDescription
      ]))
  }
}

/**
  Derivatives
*/
extension Parser {
  func fallback(_ a: A) -> Parser<A> {
    return self.handle { _ in a }
  }

  /**
   * sectionize
   *
   * Wrap the description of this parser in a `SectionDesc`.
   */
  func sectionize(_ tag: String,
                  _ name: String,
                  _ explain: String) -> Parser<A> {
    let desc = SectionDesc(
      tag: tag,
      name: name,
      desc: explain,
      child: matchDescription)

    return Parser(desc, output: output)
  }

  /**
   * topLevel
   *
   * Version of this parser where the description has been updated to indicate
   * that it is used to parse the whole argument list from the CLI. When
   * printing the usage statement, we will prepend the name of the app to the
   * front of the description to show this to users.
   */
  var topLevel: Parser<A> {
    let appPath = CommandLine.arguments.first!
    let appName = (appPath as NSString).lastPathComponent
    let desc = SequenceDesc(children: [CmdDesc(cmd: appName), matchDescription])
    return Parser(desc, output: output)
  }

  /**
   * withExpandedDesc
   *
   * Version of this parser where the description has been expanded to span
   * multiple lines, if it can.
   */
  var withExpandedDesc: Parser<A> {
    switch matchDescription {
    case let choice as ChoiceDesc:
      return Parser(choice.expanded, output: output)

    default:
      return self
    }
  }

  func describe(_ description: ParserDescription) -> Parser<A> {
    return Parser(description, output: self.output)
  }

  static var passthrough: Parser<NSNull> {
    return Parser<NSNull>(SequenceDesc(children: [])) { tokens in
      return (tokens, NSNull())
    }
  }

  static var noRemaining: Parser<NSNull> { get {
    return Parser<NSNull>(SequenceDesc(children: [])) { tokens in
      if tokens.count > 0 {
        throw ParseError.custom("There were remaining tokens \(tokens)")
      }
      return ([], NSNull())
    }
  }}

  static func fail(_ error: ParseError) -> Parser<A> {
    return Parser<A>(ChoiceDesc(children: [])) { _ in
      throw error
    }
  }

  static func single(_ description: ParserDescription, f: @escaping (String) throws -> A) -> Parser<A> {
    return Parser<A>(description) { tokens in
      guard let actual = tokens.first else {
        throw ParseError.endOfInput
      }
      return try (Array(tokens.dropFirst(1)), f(actual))
    }
  }

  static func ofString(_ string: String, _ constant: A) -> Parser<A> {
    return Parser.single(CmdDesc(cmd: string)) { token in
      if token != string {
        throw ParseError.doesNotMatch(token, string)
      }
      return constant
    }
  }

  static func ofFlag<T>(_ flag: String,
                        _ val: T,
                        _ explanation: String) -> Parser<T> {
    return Parser<T>
      .ofString("--" + flag, val)
      .describe(FlagDesc(name: flag, desc: explanation))
  }

  static func ofFlag(_ flag: String, _ explanation: String) -> Parser<Bool> {
    return ofFlag(flag, true, explanation).fallback(false)
  }

  static func ofFlagWithArg<A>(_ flag: String,
                               _ arg: Parser<A>,
                               _ explanation: String) -> Parser<A> {
    let description = PrimitiveDesc(name: flag, desc: explanation)
    let trimSet = CharacterSet(charactersIn: "'")
    let prefix = "--" + flag + "="
    let equalParser = Parser<A>.single(description) { token in
      var format = token
      guard let range = token.range(of: prefix) else {
        throw ParseError.doesNotMatch(prefix, token)
      }
      format.removeSubrange(range)
      format = format.trimmingCharacters(in: trimSet)
      let (_, result) = try arg.parse([format])
      return result
    }

    let sequentialParser = Parser<()>
      .ofFlag(flag, (), explanation)
      .sequence(arg)
    return Parser<A>.alternative([equalParser, sequentialParser])
  }

  static func ofCommandWithArg(_ cmd: String, _ arg: Parser<A>) -> Parser<A> {
    return Parser<()>
      .ofString(cmd, ())
      .sequence(arg)
  }

  static func ofTwoSequenced<B>(_ a: Parser<A>, _ b: Parser<B>) -> Parser<(A, B)> {
    return
      a.bind({ valueA in
        return b.fmap { valueB in
          return (valueA, valueB)
        }
      }).describe(SequenceDesc(children: [
        a.matchDescription,
        b.matchDescription
      ]))
  }

  static func ofThreeSequenced<B, C>(_ a: Parser<A>, _ b: Parser<B>, _ c: Parser<C>) -> Parser<(A, B, C)> {
    return
      a.bind({ valueA in
        return b.bind { valueB in
          return c.fmap { valueC in
            return (valueA, valueB, valueC)
          }
        }
      }).describe(SequenceDesc(children: [
        a.matchDescription,
        b.matchDescription,
        c.matchDescription
      ]))
  }

  static func ofFourSequenced<B, C, D>(_ a: Parser<A>, _ b: Parser<B>, _ c: Parser<C>, _ d: Parser<D>) -> Parser<(A, B, C, D)> {
    return
      a.bind({ valueA in
        return b.bind { valueB in
          return c.bind { valueC in
            return d.fmap { valueD in
              return (valueA, valueB, valueC, valueD)
            }
          }
        }
      }).describe(SequenceDesc(children: [
        a.matchDescription,
        b.matchDescription,
        c.matchDescription,
        d.matchDescription
      ]))
  }

  static func alternative(_ parsers: [Parser<A>]) -> Parser<A> {
    let descs = parsers.map { $0.matchDescription }
    return Parser<A>(ChoiceDesc(children: descs)) { tokens in
      for parser in parsers {
        do {
          return try parser.parse(tokens)
        } catch {}
      }
      throw ParseError.doesNotMatch(parsers.description, tokens.description)
    }
  }

  static func manyCount(_ count: Int, _ parser: Parser<A>) -> Parser<[A]> {
    return self.manySepCount(count, parser, Parser.passthrough)
  }

  static func manySepCount<B>(_ count: Int, _ parser: Parser<A>, _ separator: Parser<B>) -> Parser<[A]> {
    assert(count >= 0, "Count should be >= 0")
    let desc = AtleastDesc(lowerBound: count,
                           child: parser.matchDescription,
                           sep: separator.matchDescription)

    return Parser<[A]>(desc) { tokens in
      var values: [A] = []
      var runningArgs = tokens
      var parseCount = 0

      do {
        while (runningArgs.count > 0) {
          // Extract the main parsed value
          let (remainder, value) = try parser.parse(runningArgs)
          parseCount += 1
          runningArgs = remainder
          values.append(value)

          // Add the separator, will break out if separator parse fails
          let (nextRemainder, _) = try separator.parse(runningArgs)
          runningArgs = nextRemainder
        }
      } catch { }

      if (parseCount < count) {
        throw ParseError.custom("Only \(parseCount) of \(parser)")
      }
      return (runningArgs, values)
    }
  }

  static func manyTill<B>(_ terminatingParser: Parser<B>,  _ parser: Parser<A>) -> Parser<[A]> {
    let desc = SequenceDesc(children: [
      AtleastDesc(lowerBound: 0, child: parser.matchDescription),
      OptionalDesc(child: terminatingParser.matchDescription)
    ])

    return Parser<[A]>(desc) { tokens in
      var values: [A] = []
      var runningArgs = tokens

      while (runningArgs.count > 0) {
        do {
          let _ = try terminatingParser.parse(runningArgs)
          break
        } catch {
          let output = try parser.parse(runningArgs)
          runningArgs = output.0
          values.append(output.1)
        }
      }
      return (runningArgs, values)
    }
  }

  static func many(_ parser: Parser<A>) -> Parser<[A]> {
    return self.manyCount(0, parser)
  }

  static func alternativeMany(_ parsers: [Parser<A>]) -> Parser<[A]> {
    return Parser.many(Parser.alternative(parsers))
  }

  static func alternativeMany(_ count: Int, _ parsers: [Parser<A>]) -> Parser<[A]> {
    return Parser.manyCount(count, Parser.alternative(parsers))
  }

  static func union<B : SetAlgebra>(_ parsers: [Parser<B>]) -> Parser<B> {
    return Parser.union(0, parsers)
  }

  static func union<B : SetAlgebra>(_ count: Int, _ parsers: [Parser<B>]) -> Parser<B> {
    return Parser<B>
      .alternativeMany(count, parsers)
      .fmap { sets in
        var result = B()
        for set in sets {
          result.formUnion(set)
        }
        return result
      }
  }

  static func accumulate<B : Accumulator>(_ count: Int, _ parsers: [Parser<B>]) -> Parser<B> {
    return Parser<B>
      .alternativeMany(count, parsers)
      .fmap { values in
        var accumulator = B()
        for value in values {
          accumulator = accumulator.append(value)
        }
        return accumulator
      }
  }

  static func exhaustive(_ parser: Parser<A>) -> Parser<A> {
    return Parser
      .ofTwoSequenced(parser, Parser.noRemaining)
      .fmap { (original, _) in
        return original
      }
  }
}

public protocol Parsable {
  static var parser: Parser<Self> { get }
}
