/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation

public final class BridgeOutput {
  public private(set) var answers: [BridgeAnswer] = []
  public private(set) var failed = false
  public private(set) var error: String?

  public init() {}

  /// One of the command's answers. One the host could not report is refused, and fails the command.
  @discardableResult
  public func write(_ answer: BridgeAnswer) -> Bool {
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
    answers.append(.accessibility(answer))
  }

  /// A dynamic-store snapshot, carried as the binary property list it is.
  @discardableResult
  public func write(propertyList object: Any) -> Bool {
    do {
      answers.append(.dynamicStoreSnapshot(try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)))
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
    BridgeResult(exitCode: failed ? 1 : status, error: error, answers: answers)
  }

  /// The snapshot the command wrote, if it wrote one.
  public var propertyList: Data? {
    finish(status: 0).propertyList
  }
}
