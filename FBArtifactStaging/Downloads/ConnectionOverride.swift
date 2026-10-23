/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Where to open a download's connection instead of the address its URL's host resolves to.
///
/// Only the connection goes elsewhere: the URL's host is still the name TLS verifies the server's certificate against
/// and the HTTP `Host` it asks for, so the server is reached as though DNS had answered with `host`.
public struct ConnectionOverride: Sendable {

  /// A host name or an IPv4 or IPv6 address, without brackets.
  public let host: String
  public let port: UInt16

  public init(host: String, port: UInt16) {
    self.host = host
    self.port = port
  }
}
