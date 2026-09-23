/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Foundation
import XPC

/// How a CoreDevice feature fails. Callers switch on `unsupported` to choose a fallback; the other
/// three are operational and surface as they are.
enum SimulatorCoreDeviceError: Error, LocalizedError {
  /// The runtime does not vend the feature, field or capability named.
  case unsupported(String)
  /// The service exists but could not be reached or answered with an error.
  case unavailable(String)
  /// The service answered with something the protocol does not describe.
  case malformed(String)
  /// The service did not answer within the request's deadline.
  case timedOut

  var errorDescription: String? {
    switch self {
    case let .unsupported(detail): "Simulator CoreDevice capability unavailable: \(detail)"
    case let .unavailable(detail): "Simulator CoreDevice service unavailable: \(detail)"
    case let .malformed(detail): "Invalid simulator CoreDevice response: \(detail)"
    case .timedOut: "Timed out waiting for the simulator CoreDevice reply"
    }
  }
}

enum SimulatorCoreDevice {
  static let cancellationKey = "CoreDevice.XPCMessageKey.cancellationRequested"

  static func installedVersion() throws -> String {
    let url = URL(fileURLWithPath: "/Library/Developer/PrivateFrameworks/CoreDevice.framework")
    guard let version = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
      throw SimulatorCoreDeviceError.unsupported("CoreDevice version metadata")
    }
    return version
  }

  static func request(action: String, deviceID: String, version: String, input: xpc_object_t) throws -> xpc_object_t {
    let parts = version.split(separator: ".", omittingEmptySubsequences: false)
    let components = parts.compactMap { UInt64($0) }
    guard !components.isEmpty, components.count == parts.count else {
      throw SimulatorCoreDeviceError.unavailable("Invalid CoreDevice version \(version)")
    }
    return dictionary([
      "CoreDevice.actionIdentifier": xpc_string_create(action),
      "CoreDevice.deviceIdentifier": xpc_string_create(deviceID),
      "CoreDevice.invocationIdentifier": xpc_string_create(UUID().uuidString),
      "CoreDevice.CoreDeviceDDIProtocolVersion": xpc_int64_create(1),
      "CoreDevice.coreDeviceVersion": dictionary([
        "components": array(components.map(xpc_uint64_create)),
        "originalComponentsCount": xpc_int64_create(Int64(components.count)),
        "stringValue": xpc_string_create(version),
      ]),
      "CoreDevice.input": input,
    ])
  }

  static func dictionary(_ values: [String: xpc_object_t]) -> xpc_object_t {
    let result = xpc_dictionary_create(nil, nil, 0)
    for (key, value) in values { xpc_dictionary_set_value(result, key, value) }
    return result
  }

  static func array(_ values: [xpc_object_t]) -> xpc_object_t {
    let result = xpc_array_create(nil, 0)
    for value in values { xpc_array_append_value(result, value) }
    return result
  }

  static func connect(simulator: Simulator, service: String) throws -> xpc_connection_t {
    do {
      return try SimulatorXPCConnection.connect(simulator: simulator, service: service)
    } catch let error as SimulatorXPCConnectionError {
      throw SimulatorCoreDeviceError(connection: error)
    }
  }
}

extension SimulatorCoreDeviceError {
  /// A service the runtime does not vend, and a toolchain without the simulator XPC symbols, are
  /// both a missing capability; everything else is operational.
  init(connection error: SimulatorXPCConnectionError) {
    switch error {
    case .symbolsUnavailable:
      self = .unsupported("Simulator XPC symbols")
    case let .lookupFailed(service, underlying):
      self = error.isServiceUnsupported ? .unsupported(service) : .unavailable(underlying?.localizedDescription ?? service)
    case .connectionFailed:
      self = .unavailable("Simulator XPC connection")
    }
  }
}
