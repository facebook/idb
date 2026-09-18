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

@objc public final class ProxyServiceStaticFuncs: NSObject {

  @objc(buildHTTPProxyDict:port:)
  public static func buildHTTPProxyDict(host: String, port: Int32) -> [String: Any] {
    ["HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port as NSNumber, "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port as NSNumber, "FTPPassive": 1, "ExceptionsList": ["*.local", "169.254/16"]]
  }

  @objc(buildSOCKSProxyDict:port:)
  public static func buildSOCKSProxyDict(host: String, port: Int32) -> [String: Any] {
    ["SOCKSEnable": 1, "SOCKSProxy": host, "SOCKSPort": port as NSNumber, "FTPPassive": 1, "ExceptionsList": ["*.local", "169.254/16"]]
  }

  @objc(buildEmptyProxyDict)
  public static func buildEmptyProxyDict() -> [String: Any] {
    ["FTPPassive": 1]
  }

  @objc(handleProxyAction:arguments:)
  public static func handleProxyAction(action: String, arguments: [String]) -> Int {
    let store = FBNetworkConfigurationStore.proxy()
    guard let store else {
      return 1
    }

    if action == "list" {
      let read = store.readConfiguration()
      guard let read else {
        return 1
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
      return 1
    }

    let proxyDict: [String: Any]
    if action == "set" {
      if arguments.count < 2 {
        NSLog("[ProxyService] set requires <host> <port> [http|socks]")
        return 1
      }
      let host = arguments[0]
      let port = (arguments[1] as NSString).intValue
      let type = arguments.count >= 3 ? arguments[2] : "http"

      if type == "socks" {
        proxyDict = ProxyServiceStaticFuncs.buildSOCKSProxyDict(host: host, port: port)
      } else {
        proxyDict = ProxyServiceStaticFuncs.buildHTTPProxyDict(host: host, port: port)
      }
      NSLog("[ProxyService] Setting %@ proxy to %@:%d", type, host, port)
    } else if action == "clear" {
      proxyDict = ProxyServiceStaticFuncs.buildEmptyProxyDict()
      NSLog("[ProxyService] Clearing proxy settings")
    } else {
      NSLog("[ProxyService] Unknown action: %@. Use 'set', 'clear', or 'list'.", action)
      return 1
    }

    let success = store.writeConfiguration(proxyDict)

    guard success else {
      return 1
    }

    store.notifyChange()

    NSLog("[ProxyService] Proxy settings updated successfully")
    return 0
  }
}
