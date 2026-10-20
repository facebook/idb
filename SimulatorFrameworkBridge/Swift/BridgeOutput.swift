/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation

public final class BridgeOutput {
  public private(set) var values: [BridgeJSONValue] = []
  public private(set) var answers: [BridgeServiceAnswer] = []
  public private(set) var propertyList: Data?
  public private(set) var accessibility: BridgeAXAnswer?
  public private(set) var failed = false
  public private(set) var error: String?

  public init() {}

  @discardableResult
  public func write(_ object: Any) -> Bool {
    do {
      values.append(try BridgeJSONValue(foundationValue: object))
      return true
    } catch {
      NSLog("[SimulatorFrameworkBridge] Could not encode command output: %@", error as NSError)
      failure("Could not encode command output: \(error.localizedDescription)")
      return false
    }
  }

  /// One of the command's answers. One the host could not report is refused, and fails the command.
  @discardableResult
  public func write(_ answer: BridgeServiceAnswer) -> Bool {
    do {
      _ = try answer.jsonLine()
      answers.append(answer)
      return true
    } catch {
      NSLog("[SimulatorFrameworkBridge] Could not encode command output: %@", error as NSError)
      failure("Could not encode command output: \(error.localizedDescription)")
      return false
    }
  }

  /// An accessibility command's answer, which the frame carries in its own shape.
  public func write(accessibility answer: BridgeAXAnswer) {
    accessibility = answer
  }

  @discardableResult
  public func write(propertyList object: Any) -> Bool {
    do {
      propertyList = try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
      return true
    } catch {
      failure("Could not encode property-list output: \(error.localizedDescription)")
      return false
    }
  }

  @discardableResult
  public func failure(_ message: String) -> Int {
    failed = true
    if error == nil { error = message }
    return 1
  }

  public func finish(status: Int32) -> BridgeResult {
    BridgeResult(exitCode: failed ? 1 : status, values: values, error: error, answers: answers, propertyList: propertyList, accessibility: accessibility)
  }
}
