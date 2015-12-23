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
      return Command.Help(nil)
    }
  }
}

public enum ParseError : ErrorType {
  case EndOfInput
  case DoesNotMatch(String, String)
  case InvalidNumber
  case InvalidPath

  static func DoesNotMatchAnyOf(matches: [String]) -> ParseError {
    let inner = (matches as NSArray).componentsJoinedByString(", ")
    return .DoesNotMatch("any of", "[\(inner)]")
  }
}

/**
 Protocol for parsing a list of tokens.
 */
public struct Parser<A> {
  let output: [String] throws -> ([String], A)

  func parse(tokens: [String]) throws -> ([String], A) {
    let (nextTokens, value) = try output(tokens)
    return (nextTokens, value)
  }
}

/**
  Primitives
*/
extension Parser {
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
extension Parser {
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

  static func ofString(string: String, _ constant: A) -> Parser<A> {
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

  static func succeeded(token: String, _ by: Parser<A>) -> Parser<A> {
    return Parser<()>
      .ofString(token, ())
      .sequence(by)
  }

  static func ofTwo<B>(a: Parser<A>, _ b: Parser<B>) -> Parser<(A, B)> {
    return a.bind { valueA in
      return b.fmap { valueB in
        return (valueA, valueB)
      }
    }
  }

  static func alternative(parsers: [Parser<A>]) -> Parser<A> {
    return Parser<A>() { tokens in
      for parser in parsers {
        do {
          return try parser.parse(tokens)
        } catch {}
      }
      throw ParseError.EndOfInput
    }
  }

  static func ofMany(parsers: [Parser<A>]) -> Parser<[A]> {
    return self.ofManyCount(0, parsers)
  }

  static func ofAny(parsers: [Parser<A>]) -> Parser<A> {
    return self.ofManyCount(1, parsers)
      .fmap { $0.first! }
  }

  static func ofManyCount(count: Int, _ parsers: [Parser<A>]) -> Parser<[A]> {
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

public protocol Parsable {
  static func parser() -> Parser<Self>
}
