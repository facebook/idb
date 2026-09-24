/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import SimulatorFrameworkBridgeProtocol

public final class BridgeOutput {
  public private(set) var values: [BridgeJSONValue] = []
  public private(set) var failed = false

  public init() {}

  @discardableResult
  public func write(_ object: Any) -> Bool {
    do {
      values.append(try BridgeJSONValue(foundationValue: object))
      return true
    } catch {
      NSLog("[SimulatorFrameworkBridge] Could not encode command output: %@", error as NSError)
      failed = true
      return false
    }
  }

  public func finish(status: Int32) -> BridgeResult {
    BridgeResult(exitCode: failed ? 1 : status, values: values)
  }
}
