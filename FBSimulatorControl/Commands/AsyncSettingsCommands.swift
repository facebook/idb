/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Swift-native async/await counterpart of `FBSimulatorSettingsCommandsProtocol`.
public protocol AsyncSettingsCommands: AnyObject {

  func setSetting(_ setting: FBSimulatorSetting, enabled: Bool) async throws

  func setPreference(_ name: String, value: String, type: String?, domain: String?) async throws

  func getCurrentPreference(_ name: String, domain: String?) async throws -> String

  func grantAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws

  func revokeAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws

  func grantAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws

  func revokeAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws

  func updateContacts(_ databaseDirectory: String) async throws

  func clearContacts() async throws

  func clearPhotos() async throws
}

/// Default bridge implementation against the legacy
/// `FBSimulatorSettingsCommandsProtocol`.
extension AsyncSettingsCommands where Self: FBSimulatorSettingsCommandsProtocol {

  public func setSetting(_ setting: FBSimulatorSetting, enabled: Bool) async throws {
    try await bridgeFBFutureVoid(self.setSetting(setting, enabled: enabled))
  }

  public func setPreference(_ name: String, value: String, type: String?, domain: String?) async throws {
    try await bridgeFBFutureVoid(self.setPreference(name, value: value, type: type, domain: domain))
  }

  public func getCurrentPreference(_ name: String, domain: String?) async throws -> String {
    return try await bridgeFBFuture(self.getCurrentPreference(name, domain: domain)) as String
  }

  public func grantAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws {
    try await bridgeFBFutureVoid(self.grantAccess(bundleIDs, toServices: services))
  }

  public func revokeAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws {
    try await bridgeFBFutureVoid(self.revokeAccess(bundleIDs, toServices: services))
  }

  public func grantAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws {
    try await bridgeFBFutureVoid(self.grantAccess(bundleIDs, toDeeplink: scheme))
  }

  public func revokeAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws {
    try await bridgeFBFutureVoid(self.revokeAccess(bundleIDs, toDeeplink: scheme))
  }

  public func updateContacts(_ databaseDirectory: String) async throws {
    try await bridgeFBFutureVoid(self.updateContacts(databaseDirectory))
  }

  public func clearContacts() async throws {
    try await bridgeFBFutureVoid(self.clearContacts())
  }

  public func clearPhotos() async throws {
    try await bridgeFBFutureVoid(self.clearPhotos())
  }
}
