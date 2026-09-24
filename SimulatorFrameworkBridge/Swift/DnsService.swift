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

  @objc(handleDnsAction:arguments:)
  public static func handleDnsAction(action: String, arguments: [String]) -> Int {
    handleDnsAction(action: action, arguments: arguments, output: nil)
  }

  static func handleDnsAction(action: String, arguments: [String], output: BridgeOutput?) -> Int {
    NetworkConfigurationService(
      name: "DNS",
      logTag: "[DnsService]",
      store: FBNetworkConfigurationStore.dns(),
      clearedConfiguration: [:],
      clearingMessage: "Clearing DNS configuration",
      updatedMessage: "DNS configuration updated successfully"
    ) { servers in
      guard !servers.isEmpty else {
        NSLog("[DnsService] set requires at least one DNS server address")
        return nil
      }
      NSLog("[DnsService] Setting DNS servers to %@", servers.joined(separator: ", "))
      return buildDnsDict(servers: servers)
    }.handle(action: action, arguments: arguments, output: output)
  }
}
