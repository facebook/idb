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

@objc public final class DnsServiceStaticFuncs: NSObject {

  @objc(buildDnsDict:)
  public static func buildDnsDict(servers: [String]) -> [String: Any] {
    ["ServerAddresses": servers]
  }

  @objc(buildEmptyDnsDict)
  public static func buildEmptyDnsDict() -> [String: Any] {
    [:]
  }

  @objc(handleDnsAction:arguments:)
  public static func handleDnsAction(action: String, arguments: [String]) -> Int {
    handleDnsAction(action: action, arguments: arguments, output: nil)
  }

  static func handleDnsAction(action: String, arguments: [String], output: BridgeOutput?) -> Int {
    let store = FBNetworkConfigurationStore.dns()
    guard let store else {
      return output?.failure("The DNS private API is unavailable") ?? 1
    }

    let selectedAction = NetworkConfigurationAction(rawValue: action)
    if selectedAction == .list {
      let read = store.readConfiguration()
      guard let read else {
        return output?.failure("Could not read DNS configuration") ?? 1
      }
      if let output {
        return output.write(read.configuration ?? [:]) ? 0 : 1
      }
      if let dict = read.configuration {
        if let json = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
          let str = String(data: json, encoding: .utf8)
        {
          // patternlint-disable-next-line avoid-print-to-prevent-production-overhead
          print(str)
        }
      } else {
        // patternlint-disable-next-line avoid-print-to-prevent-production-overhead
        print("{}")
      }
      return 0
    }

    guard store.prepareToWrite() else {
      return output?.failure("Could not prepare DNS configuration for writing") ?? 1
    }

    let dnsDict: [String: Any]
    if selectedAction == .set {
      if arguments.isEmpty {
        NSLog("[DnsService] set requires at least one DNS server address")
        return output?.failure("Invalid DNS set arguments") ?? 1
      }
      dnsDict = DnsServiceStaticFuncs.buildDnsDict(servers: arguments)
      NSLog("[DnsService] Setting DNS servers to %@", arguments.joined(separator: ", "))
    } else if selectedAction == .clear {
      dnsDict = DnsServiceStaticFuncs.buildEmptyDnsDict()
      NSLog("[DnsService] Clearing DNS configuration")
    } else {
      NSLog("[DnsService] Unknown action: %@. Use 'set', 'clear', or 'list'.", action)
      return output?.failure("Unknown DNS action") ?? 1
    }

    let success = store.writeConfiguration(dnsDict)

    guard success else {
      return output?.failure("Could not write DNS configuration") ?? 1
    }

    store.notifyChange()

    NSLog("[DnsService] DNS configuration updated successfully")
    return 0
  }
}
