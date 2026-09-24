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
  public private(set) var propertyList: Data?
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

  @discardableResult
  public func write(json data: Data) -> BridgeJSONValue? {
    do {
      let value = try JSONDecoder().decode(BridgeJSONValue.self, from: data)
      return write(value.foundationValue) ? value : nil
    } catch {
      failure("Could not decode command output: \(error.localizedDescription)")
      return nil
    }
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
    BridgeResult(exitCode: failed ? 1 : status, values: values, error: error, propertyList: propertyList)
  }
}
