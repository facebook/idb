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

public enum ParseError : ErrorType, CustomStringConvertible {
  case EndOfInput
  case DoesNotMatch(String, String)
  case CouldNotInterpret(String, String)
  case Custom(String)

  public var description: String { get {
    switch self {
    case .EndOfInput:
      return "End of Input"
    case .DoesNotMatch(let expected, let actual):
      return "'\(actual)' does not match '\(expected)'"
    case .CouldNotInterpret(let typeName, let actual):
      return "\(actual) could not be interpreted as \(typeName)"
    case .Custom(let message):
      return message
    }
  }}
}

/**
 Protocol for parsing a list of tokens.
 */
public struct Parser<A> : CustomStringConvertible {
  let matchDescription: String
  let output: [String] throws -> ([String], A)

  init(_ matchDescription: String, output: [String] throws -> ([String], A)) {
    self.matchDescription = matchDescription
    self.output = output
  }

  public func parse(tokens: [String]) throws -> ([String], A) {
    let (nextTokens, value) = try output(tokens)
    return (nextTokens, value)
  }

  public var description: String { get {
    return self.matchDescription
  }}
}

/**
  Primitives
*/
extension Parser {
  func fmap<B>(f: A throws -> B) -> Parser<B> {
    return Parser<B>(self.matchDescription) { input in
      let (tokensOut, a) = try self.output(input)
      let b = try f(a)
      return (tokensOut, b)
    }
  }

  func bind<B>(f: A -> Parser<B>) -> Parser<B> {
    return Parser<B>(self.matchDescription) { tokens in
      let (tokensA, valueA) = try self.parse(tokens)
      let (tokensB, valueB) = try f(valueA).parse(tokensA)
      return (tokensB, valueB)
    }
  }

  func optional() -> Parser<A?> {
    return Parser<A?>(self.matchDescription) { tokens in
      do {
        let (tokens, value) = try self.parse(tokens)
        return (tokens, Optional.Some(value))
      } catch {
        return (tokens, nil)
      }
    }
  }

  func handle(f: ParseError -> A) -> Parser<A> {
    return Parser<A>(self.matchDescription) { tokens in
      do {
        return try self.parse(tokens)
      } catch let error as ParseError {
        return (tokens, f(error))
      }
    }
  }

  func sequence<B>(p: Parser<B>) -> Parser<B> {
    return self
      .bind({ _ in p })
      .describe("\(self) followed by \(p)")
  }
}

/**
  Derivatives
*/
extension Parser {
  func fallback(a: A) -> Parser<A> {
    return self.handle { _ in a }
  }

  func describe(description: String) -> Parser<A> {
    return Parser(description, output: self.output)
  }

  static var passthrough: Parser<NSNull> { get {
    return Parser<NSNull>("") { tokens in
      return (tokens, NSNull())
    }
  }}

  static var noRemaining: Parser<NSNull> { get {
    return Parser<NSNull>("No Remaining") { tokens in
      if tokens.count > 0 {
        throw ParseError.Custom("There were remaining tokens \(tokens)")
      }
      return ([], NSNull())
    }
  }}

  static func fail(error: ParseError) -> Parser<A> {
    return Parser<A>("fail Parser") { _ in
      throw error
    }
  }

  static func single(description: String, f: String throws -> A) -> Parser<A> {
    return Parser<A>(description) { tokens in
      guard let actual = tokens.first else {
        throw ParseError.EndOfInput
      }
      return try (Array(tokens.dropFirst(1)), f(actual))
    }
  }

  static func ofString(string: String, _ constant: A) -> Parser<A> {
    return Parser.single(string) { token in
      if token != string {
        throw ParseError.DoesNotMatch(token, string)
      }
      return constant
    }
  }

  static func ofFlag(flag: String) -> Parser<Bool> {
    return Parser<Bool>
      .ofString(flag, true)
      .fallback(false)
      .describe("Flag \(flag)")
  }

  static func succeeded(token: String, _ by: Parser<A>) -> Parser<A> {
    return Parser<()>
      .ofString(token, ())
      .sequence(by)
      .describe("\(token) followed by \(by)")
  }

  static func ofTwoSequenced<B>(a: Parser<A>, _ b: Parser<B>) -> Parser<(A, B)> {
    return
      a.bind({ valueA in
        return b.fmap { valueB in
          return (valueA, valueB)
        }
      })
      .describe("\(a) followed by \(b)")
  }

  static func ofThreeSequenced<B, C>(a: Parser<A>, _ b: Parser<B>, _ c: Parser<C>) -> Parser<(A, B, C)> {
    return
      a.bind({ valueA in
        return b.bind { valueB in
          return c.fmap { valueC in
            return (valueA, valueB, valueC)
          }
        }
      })
      .describe("\(a) followed by \(b) followed by \(c)")
  }

  static func ofFourSequenced<B, C, D>(a: Parser<A>, _ b: Parser<B>, _ c: Parser<C>, _ d: Parser<D>) -> Parser<(A, B, C, D)> {
    return
      a.bind({ valueA in
        return b.bind { valueB in
          return c.bind { valueC in
            return d.fmap { valueD in
              return (valueA, valueB, valueC, valueD)
            }
          }
        }
      })
      .describe("\(a) followed by \(b) followed by \(c) followed by \(d)")
  }

  static func alternative(parsers: [Parser<A>]) -> Parser<A> {
    return Parser<A>("Any of \(parsers)") { tokens in
      for parser in parsers {
        do {
          return try parser.parse(tokens)
        } catch {}
      }
      throw ParseError.DoesNotMatch(parsers.description, tokens.description)
    }
  }

  static func manyCount(count: Int, _ parser: Parser<A>) -> Parser<[A]> {
    return self.manySepCount(count, parser, Parser.passthrough)
  }

  static func manySepCount<B>(count: Int, _ parser: Parser<A>, _ separator: Parser<B>) -> Parser<[A]> {
    assert(count >= 0, "Count should be >= 0")
    return Parser<[A]>("At least \(count) of \(parser)") { tokens in
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
        throw ParseError.Custom("Only \(parseCount) of \(parser)")
      }
      return (runningArgs, values)
    }
  }

  static func manyTill<B>(terminatingParser: Parser<B>,  _ parser: Parser<A>) -> Parser<[A]> {
    return Parser<[A]>("Many of \(parser)") { tokens in
      var values: [A] = []
      var runningArgs = tokens

      while (runningArgs.count > 0) {
        do {
          try terminatingParser.parse(runningArgs)
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

  static func many(parser: Parser<A>) -> Parser<[A]> {
    return self.manyCount(0, parser)
  }

  static func alternativeMany(parsers: [Parser<A>]) -> Parser<[A]> {
    return Parser.many(Parser.alternative(parsers))
  }

  static func alternativeMany(count: Int, _ parsers: [Parser<A>]) -> Parser<[A]> {
    return Parser.manyCount(count, Parser.alternative(parsers))
  }

  static func union<B : SetAlgebraType>(parsers: [Parser<B>]) -> Parser<B> {
    return Parser.union(0, parsers)
  }

  static func union<B : SetAlgebraType>(count: Int, _ parsers: [Parser<B>]) -> Parser<B> {
    return Parser<B>
      .alternativeMany(count, parsers)
      .fmap { sets in
        var result = B()
        for set in sets {
          result.unionInPlace(set)
        }
        return result
      }
  }

  static func accumulate<B : Accumulator>(count: Int, _ parsers: [Parser<B>]) -> Parser<B> {
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

  static func exhaustive(parser: Parser<A>) -> Parser<A> {
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
