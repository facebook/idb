/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum BridgeProtocolError: Error, Equatable {
  case invalidJSONValue
  case unsupportedVersion(Int)
  case mismatchedResponse
  case invalidFrameSize(Int)
}

public struct BridgeRequest: Codable, Equatable, Sendable {
  public static let currentVersion = 1
  public let version: Int
  public let id: String
  public let command: BridgeCommand

  public init(command: BridgeCommand, id: String = UUID().uuidString) {
    version = Self.currentVersion
    self.id = id
    self.command = command
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(self)
  }

  public var arguments: [String] {
    get throws {
      ["rpc", String(decoding: try encoded(), as: UTF8.self)]
    }
  }

  public static func decode(_ data: Data) throws -> Self {
    // The version is checked before the command so a newer command shape reports the version gap,
    // not a decoding failure.
    let envelope = try JSONDecoder().decode(Envelope.self, from: data)
    guard envelope.version == currentVersion else { throw BridgeProtocolError.unsupportedVersion(envelope.version) }
    return try JSONDecoder().decode(Self.self, from: data)
  }

  /// The identity a request carries even when the rest of it cannot be decoded, so a reply can still name it.
  public static func identity(of data: Data) -> String? {
    (try? JSONDecoder().decode(Identity.self, from: data))?.id
  }

  private struct Envelope: Decodable {
    let version: Int
    let id: String
  }

  private struct Identity: Decodable {
    let id: String?
  }
}

public struct BridgeResult: Codable, Equatable, Sendable {
  public let exitCode: Int32
  public let values: [BridgeJSONValue]
  public let error: String?
  public let propertyList: Data?

  public init(exitCode: Int32, values: [BridgeJSONValue] = [], error: String? = nil, propertyList: Data? = nil) {
    self.exitCode = exitCode
    self.values = values
    self.error = error
    self.propertyList = propertyList
  }
}

public struct BridgeResponse: Codable, Equatable, Sendable {
  public let version: Int
  public let id: String?
  public let result: BridgeResult

  public init(request: BridgeRequest, result: BridgeResult) {
    self.init(id: request.id, result: result)
  }

  public init(id: String?, result: BridgeResult) {
    version = BridgeRequest.currentVersion
    self.id = id
    self.result = result
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try encoder.encode(self)
  }

  public static func decode(_ data: Data, for request: BridgeRequest) throws -> Self {
    let response = try JSONDecoder().decode(Self.self, from: data)
    guard response.version == BridgeRequest.currentVersion else { throw BridgeProtocolError.unsupportedVersion(response.version) }
    guard response.id == request.id else { throw BridgeProtocolError.mismatchedResponse }
    return response
  }
}

public enum BridgeFrame {
  public static let maximumSize = 16 * 1024 * 1024

  public static func header(forSize size: Int) throws -> Data {
    guard size > 0, size <= maximumSize else { throw BridgeProtocolError.invalidFrameSize(size) }
    var length = UInt32(size).bigEndian
    return withUnsafeBytes(of: &length) { Data($0) }
  }

  public static func size(fromHeader header: Data) throws -> Int {
    guard header.count == 4 else { throw BridgeProtocolError.invalidFrameSize(header.count) }
    let size = header.reduce(0) { ($0 << 8) | Int($1) }
    guard size > 0, size <= maximumSize else { throw BridgeProtocolError.invalidFrameSize(size) }
    return size
  }
}
