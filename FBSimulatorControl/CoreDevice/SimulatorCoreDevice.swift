/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Darwin
import Foundation
import XPC

enum SimulatorCoreDeviceError: Error, LocalizedError {
  case unavailable(String)

  var errorDescription: String? {
    switch self {
    case let .unavailable(detail): "Simulator CoreDevice service unavailable: \(detail)"
    }
  }
}

enum SimulatorCoreDevice {
  static let cancellationKey = "CoreDevice.XPCMessageKey.cancellationRequested"

  static func installedVersion() throws -> String {
    let url = URL(fileURLWithPath: "/Library/Developer/PrivateFrameworks/CoreDevice.framework")
    guard let version = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
      throw SimulatorCoreDeviceError.unavailable("CoreDevice version metadata")
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

  private typealias EndpointFromPort = @convention(c) (mach_port_t, UInt64, UInt64) -> Unmanaged<AnyObject>?
  private typealias ConnectionFromEndpoint = @convention(c) (xpc_object_t) -> Unmanaged<AnyObject>?
  private typealias EnableSim2Host = @convention(c) (xpc_connection_t) -> Void

  static func connect(simulator: Simulator, service: String) throws -> xpc_connection_t {
    guard let handle = dlopen(nil, RTLD_NOW) else { throw SimulatorCoreDeviceError.unavailable("XPC symbols") }
    defer { dlclose(handle) }
    guard
      let endpointFromPort = symbol(handle, "xpc_endpoint_create_mach_port_4sim", as: EndpointFromPort.self),
      let connectionFromEndpoint = symbol(handle, "xpc_connection_create_from_endpoint", as: ConnectionFromEndpoint.self),
      let enableSim2Host = symbol(handle, "xpc_connection_enable_sim2host_4sim", as: EnableSim2Host.self)
    else { throw SimulatorCoreDeviceError.unavailable("Simulator XPC symbols") }
    var error: NSError?
    let port = simulator.device.lookup(service, error: &error)
    guard port != MACH_PORT_NULL else {
      throw SimulatorCoreDeviceError.unavailable(error?.localizedDescription ?? service)
    }
    // Both Create functions return +1. The endpoint consumes the lookup's send right.
    guard let endpoint = endpointFromPort(port, 0, 0)?.takeRetainedValue() as? xpc_object_t,
      let connection = connectionFromEndpoint(endpoint)?.takeRetainedValue() as? xpc_connection_t
    else { throw SimulatorCoreDeviceError.unavailable("Simulator XPC connection") }
    enableSim2Host(connection)
    return connection
  }

  private static func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as type: T.Type) -> T? {
    guard let pointer = dlsym(handle, name) else { return nil }
    return unsafeBitCast(pointer, to: type)
  }
}
