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

private enum ProxyConfiguration {
  case http(host: String, port: Int32)
  case socks(host: String, port: Int32)
  case cleared

  init(host: String, port: Int32, type: String) {
    self = type == "socks" ? .socks(host: host, port: port) : .http(host: host, port: port)
  }

  var dictionary: [String: Any] {
    switch self {
    case let .http(host, port):
      return ["HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port as NSNumber, "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port as NSNumber, "FTPPassive": 1, "ExceptionsList": ["*.local", "169.254/16"]]
    case let .socks(host, port):
      return ["SOCKSEnable": 1, "SOCKSProxy": host, "SOCKSPort": port as NSNumber, "FTPPassive": 1, "ExceptionsList": ["*.local", "169.254/16"]]
    case .cleared:
      return ["FTPPassive": 1]
    }
  }
}

@objc public final class ProxyServiceStaticFuncs: NSObject {

  @objc(buildHTTPProxyDict:port:)
  public static func buildHTTPProxyDict(host: String, port: Int32) -> [String: Any] {
    ProxyConfiguration.http(host: host, port: port).dictionary
  }

  @objc(buildSOCKSProxyDict:port:)
  public static func buildSOCKSProxyDict(host: String, port: Int32) -> [String: Any] {
    ProxyConfiguration.socks(host: host, port: port).dictionary
  }

  @objc(buildEmptyProxyDict)
  public static func buildEmptyProxyDict() -> [String: Any] {
    ProxyConfiguration.cleared.dictionary
  }

  @objc(handleProxyAction:arguments:)
  public static func handleProxyAction(action: String, arguments: [String]) -> Int {
    handleProxyAction(action: action, arguments: arguments, output: nil)
  }

  static func handleProxyAction(action: String, arguments: [String], output: BridgeOutput?) -> Int {
    let store = FBNetworkConfigurationStore.proxy()
    guard let store else {
      return output?.failure("The proxy private API is unavailable") ?? 1
    }

    let selectedAction = NetworkConfigurationAction(rawValue: action)
    if selectedAction == .list {
      let read = store.readConfiguration()
      guard let read else {
        return output?.failure("Could not read proxy configuration") ?? 1
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
      return output?.failure("Could not prepare proxy configuration for writing") ?? 1
    }

    let proxyDict: [String: Any]
    if selectedAction == .set {
      if arguments.count < 2 {
        NSLog("[ProxyService] set requires <host> <port> [http|socks]")
        return output?.failure("Invalid proxy set arguments") ?? 1
      }
      let host = arguments[0]
      let port = (arguments[1] as NSString).intValue
      let type = arguments.count >= 3 ? arguments[2] : "http"

      proxyDict = ProxyConfiguration(host: host, port: port, type: type).dictionary
      NSLog("[ProxyService] Setting %@ proxy to %@:%d", type, host, port)
    } else if selectedAction == .clear {
      proxyDict = ProxyServiceStaticFuncs.buildEmptyProxyDict()
      NSLog("[ProxyService] Clearing proxy settings")
    } else {
      NSLog("[ProxyService] Unknown action: %@. Use 'set', 'clear', or 'list'.", action)
      return output?.failure("Unknown proxy action") ?? 1
    }

    let success = store.writeConfiguration(proxyDict)

    guard success else {
      return output?.failure("Could not write proxy configuration") ?? 1
    }

    store.notifyChange()

    NSLog("[ProxyService] Proxy settings updated successfully")
    return 0
  }
}
