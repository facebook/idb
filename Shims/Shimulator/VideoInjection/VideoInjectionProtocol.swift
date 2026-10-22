/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum ShimulatorVideoInjection {
  public static let capability = "video"
}

/// `path` plays on every camera that `frontPath` does not override.
public struct VideoInjectionParameters: Codable, Equatable, Sendable {
  public let path: String
  public let frontPath: String?
  public let loop: Bool

  public init(path: String, frontPath: String? = nil, loop: Bool) {
    self.path = path
    self.frontPath = frontPath
    self.loop = loop
  }
}
