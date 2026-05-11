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

  func currentAppearance() async throws -> FBSimulatorAppearance

  func setAppearance(_ appearance: FBSimulatorAppearance) async throws

  func currentContentSizeCategory() async throws -> FBSimulatorContentSizeCategory

  func setContentSizeCategory(_ category: FBSimulatorContentSizeCategory) async throws

  func currentStatusBarOverrides() async throws -> FBStatusBarOverride

  func overrideStatusBar(_ override: FBStatusBarOverride?) async throws

  func setPreference(_ name: String, value: String, type: String?, domain: String?) async throws

  func getCurrentPreference(_ name: String, domain: String?) async throws -> String

  func grantAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws

  func revokeAccess(_ bundleIDs: Set<String>, toServices services: Set<FBTargetSettingsService>) async throws

  func grantAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws

  func revokeAccess(_ bundleIDs: Set<String>, toDeeplink scheme: String) async throws

  func updateContacts(_ databaseDirectory: String) async throws

  func clearContacts() async throws

  func clearPhotos() async throws

  func setProxy(host: String, port: UInt, type: String) async throws

  func clearProxy() async throws

  func listProxy() async throws -> String

  func setDnsServers(_ servers: [String]) async throws

  func clearDns() async throws

  func listDns() async throws -> String

  func setHealthAuthorization(_ approved: Bool, forBundleID bundleID: String, typeIdentifiers: [String]) async throws

  func clearHealthAuthorization(forBundleID bundleID: String) async throws

  func listHealthAuthorization(forBundleID bundleID: String) async throws -> String
}
