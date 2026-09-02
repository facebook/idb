/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Timing and transport measurements for an axbridge read.
public struct FBAXBridgeProfile: Sendable, Equatable, Encodable {
  public let elementCount: Int64
  public let totalDuration: CFAbsoluteTime
  public let acquireDuration: CFAbsoluteTime
  public let readDuration: CFAbsoluteTime
  public let serializeDuration: CFAbsoluteTime
  public let traversal: FBAXTraversal
  public let machRoundTrips: Int64?
  public let hostDecodeDuration: CFAbsoluteTime?
  public let responseBytes: Int64?

  public init(
    elementCount: Int64,
    totalDuration: CFAbsoluteTime,
    acquireDuration: CFAbsoluteTime,
    readDuration: CFAbsoluteTime,
    serializeDuration: CFAbsoluteTime,
    traversal: FBAXTraversal,
    machRoundTrips: Int64? = nil,
    hostDecodeDuration: CFAbsoluteTime? = nil,
    responseBytes: Int64? = nil
  ) {
    self.elementCount = elementCount
    self.totalDuration = totalDuration
    self.acquireDuration = acquireDuration
    self.readDuration = readDuration
    self.serializeDuration = serializeDuration
    self.traversal = traversal
    self.machRoundTrips = machRoundTrips
    self.hostDecodeDuration = hostDecodeDuration
    self.responseBytes = responseBytes
  }

  enum CodingKeys: String, CodingKey {
    case elementCount = "element_count"
    case totalDurationMs = "total_duration_ms"
    case acquireDurationMs = "acquire_duration_ms"
    case readDurationMs = "read_duration_ms"
    case serializeDurationMs = "serialize_duration_ms"
    case traversal
    case machRoundTrips = "mach_round_trips"
    case hostDecodeDurationMs = "host_decode_duration_ms"
    case responseBytes = "response_bytes"
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(elementCount, forKey: .elementCount)
    try container.encode(totalDuration * 1000, forKey: .totalDurationMs)
    try container.encode(acquireDuration * 1000, forKey: .acquireDurationMs)
    try container.encode(readDuration * 1000, forKey: .readDurationMs)
    try container.encode(serializeDuration * 1000, forKey: .serializeDurationMs)
    try container.encode(traversal.rawValue, forKey: .traversal)
    try container.encode(machRoundTrips, forKey: .machRoundTrips)
    try container.encode(hostDecodeDuration.map { $0 * 1000 }, forKey: .hostDecodeDurationMs)
    try container.encode(responseBytes, forKey: .responseBytes)
  }
}

/// The backend-specific profile carried by a complete accessibility document.
public enum FBAccessibilityProfile: Sendable, Equatable, Encodable {
  case translator(FBAccessibilityProfilingData)
  case guestBridge(FBAXBridgeProfile)

  public var translatorProfile: FBAccessibilityProfilingData? {
    guard case let .translator(profile) = self else {
      return nil
    }
    return profile
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .translator(profile):
      try container.encode(profile)
    case let .guestBridge(profile):
      try container.encode(profile)
    }
  }
}

public struct FBAccessibilityAutomationState: Sendable, Equatable, Encodable {
  public let enabled: Bool
  public let asserted: Bool

  public init(enabled: Bool, asserted: Bool) {
    self.enabled = enabled
    self.asserted = asserted
  }

  enum CodingKeys: String, CodingKey {
    case enabled
    case asserted
  }
}
