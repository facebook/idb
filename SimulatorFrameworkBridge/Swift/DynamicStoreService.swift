/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

#if canImport(SimulatorFrameworkBridgeRuntime)
@_implementationOnly import SimulatorFrameworkBridgeRuntime
#endif

@objc public final class DynamicStoreServiceStaticFuncs: NSObject {
  private enum Action: String {
    case snapshot
    case restore
  }

  @objc public static func key(forName name: String) -> String? {
    switch name {
    case "dns": return "State:/Network/Global/DNS"
    case "proxy": return "State:/Network/Global/Proxies"
    default: return name.contains(":") ? name : nil
    }
  }

  @objc public static func handleDynamicStoreAction(_ action: String, arguments: [String]) -> Int32 {
    run(action: action, arguments: arguments, input: { FileHandle.standardInput.readDataToEndOfFile() })
  }

  private static func run(action: String, arguments: [String], input: () -> Data) -> Int32 {
    guard let selectedAction = Action(rawValue: action) else {
      NSLog("[DynamicStoreService] Unknown action: %@. Use 'snapshot' or 'restore'.", action)
      return 1
    }
    guard let name = arguments.first, !name.isEmpty else {
      NSLog("[DynamicStoreService] %@ requires a configd key, or one of 'dns' and 'proxy'", action)
      return 1
    }
    guard let key = key(forName: name) else {
      NSLog("[DynamicStoreService] %@ is neither a configd key nor a known alias", name)
      return 1
    }
    guard let client = FBDynamicStoreClient.open(key: key) else { return 1 }
    guard let current = client.read() else {
      NSLog("[DynamicStoreService] Cannot read the dynamic store key")
      return 1
    }
    switch selectedAction {
    case .snapshot:
      return writeSnapshot(current.value)
    case .restore:
      guard let snapshot = requestedSnapshot(input()) else { return 1 }
      switch snapshot {
      case let .present(value):
        guard client.writeValue(value) else { return 1 }
      case .absent:
        if current.value != nil && !client.removeValue() { return 1 }
      }
      client.notifyChange()
      guard let restored = client.read() else {
        NSLog("[DynamicStoreService] Cannot read back the restored value")
        return 1
      }
      return writeSnapshot(restored.value)
    }
  }

  private enum Snapshot {
    case present(Any)
    case absent
  }

  private static func requestedSnapshot(_ data: Data) -> Snapshot? {
    do {
      let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
      guard let fields = object as? [String: Any], let present = fields["present"] as? NSNumber else {
        NSLog("[DynamicStoreService] Cannot read the snapshot to restore: %@", String(describing: object as AnyObject))
        return nil
      }
      guard present.boolValue else { return .absent }
      guard let value = fields["value"] else {
        NSLog("[DynamicStoreService] The snapshot to restore is present but carries no value")
        return nil
      }
      return .present(value)
    } catch {
      NSLog("[DynamicStoreService] Cannot read the snapshot to restore: %@", error as NSError)
      return nil
    }
  }

  private static func writeSnapshot(_ value: Any?) -> Int32 {
    let snapshot: [String: Any] = value.map { ["present": true, "value": $0] } ?? ["present": false]
    do {
      let data = try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
      FileHandle.standardOutput.write(data)
      return 0
    } catch {
      NSLog("[DynamicStoreService] Cannot serialise the snapshot: %@", error as NSError)
      return 1
    }
  }
}
