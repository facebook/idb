/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Swift-native async/await counterpart of `FBDiagnosticInformationCommands`.
public protocol AsyncDiagnosticInformationCommands: AnyObject {

  func fetchDiagnosticInformation() async throws -> [String: Any]
}

/// Default bridge implementation against the legacy `FBDiagnosticInformationCommands`
/// protocol.
extension AsyncDiagnosticInformationCommands where Self: FBDiagnosticInformationCommands {

  public func fetchDiagnosticInformation() async throws -> [String: Any] {
    try await bridgeFBFutureDictionary(self.fetchDiagnosticInformation())
  }
}
