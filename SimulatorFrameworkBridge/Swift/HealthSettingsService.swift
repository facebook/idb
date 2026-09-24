/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if !os(tvOS)
import Foundation

#if canImport(SimulatorFrameworkBridgeRuntime)
@_implementationOnly import SimulatorFrameworkBridgeRuntime
#endif
// HKInternalAuthorizationStatus values, as healthd expects them (from `_HKInternalAuthorizationStatusMake`
// and `+[HDAuthorizationEntity _insertAuthorizationWith…]`). NOT the public HKAuthorizationStatus 0..4.
private let healthInternalAuthShareAndRead: UInt = 101
private let healthInternalAuthShareAndReadDenied: UInt = 104
// The default HKQuantity types used by `approve` when the caller does not specify any.
private func defaultApproveTypeIdentifiers() -> [String] {
  struct StaticVars {
    static let defaults = ["HKQuantityTypeIdentifierStepCount", "HKQuantityTypeIdentifierHeartRate", "HKQuantityTypeIdentifierActiveEnergyBurned", "HKQuantityTypeIdentifierDistanceWalkingRunning", "HKQuantityTypeIdentifierBodyMass"]
  }
  return StaticVars.defaults
}

// MARK: - JSON output helpers

private func jsonStringFromObject(obj: Any) -> String {
  do {
    let data = try JSONSerialization.data(withJSONObject: obj, options: [])
    return String(data: data, encoding: .utf8) ?? "(null)"
  } catch {
    return "\"<json-error: \(error.localizedDescription)>\""
  }
}

private func printHealthJSON(_ object: [String: Any], output: BridgeOutput?) {
  if let output {
    output.write(object)
    return
  }
  let json = jsonStringFromObject(obj: object)
  // The existing C writer stops at the first NUL.
  // patternlint-disable-next-line avoid-print-to-prevent-production-overhead
  print(String(json.prefix { $0 != "\0" }))
}

private func recordToDictionary(record: FBHealthAuthorizationRecord) -> [String: Any] {
  var out = [String: Any]()
  if let value = record.identifier {
    out["identifier"] = value
  }
  if let value = record.sharingAuthorizationAllowed {
    out["sharingAuthorizationAllowed"] = value
  }
  if let value = record.readingAuthorizationAllowed {
    out["readingAuthorizationAllowed"] = value
  }
  return out
}

// MARK: - Verb implementations

private func handleSetAction(
  client: FBHealthSettingsClient,
  bundleID: String,
  typeIdentifiers: [String],
  statusCode: UInt,
  actionName: String,
  sink: BridgeOutput?
) throws -> Int {
  let requested = !typeIdentifiers.isEmpty ? typeIdentifiers : defaultApproveTypeIdentifiers()

  let selection = FBHealthTypeSelection()
  var resolvedIdentifiers: [String] = []
  var unresolvedIdentifiers: [String] = []
  for identifier in requested {
    let resolved = try selection.resolveIdentifier(identifier)
    if resolved.boolValue {
      resolvedIdentifiers.append(identifier)
    } else {
      NSLog("[Health] Skipping unresolved HK type identifier: %@", identifier)
      unresolvedIdentifiers.append(identifier)
    }
  }
  if selection.isEmpty {
    let output: [String: Any] = ["action": actionName, "bundleID": bundleID, "ok": false, "error": "no resolvable HK types in request", "unresolvedTypes": unresolvedIdentifiers]
    printHealthJSON(output, output: sink)
    return 1
  }
  // Seed first: the daemon drops status writes for unseen bundle/type pairs.
  let seed = try client.seedAuthorization(forBundleIdentifier: bundleID, selection: selection)

  if let sink, seed.status == .timedOut {
    sink.write(["action": actionName, "bundleID": bundleID, "ok": false, "error": "Health seed timed out", "completionStatus": "timedOut"])
    return 1
  }
  let write = try client.setAuthorizationForBundleIdentifier(bundleID, selection: selection, status: statusCode)
  guard let set = write.operation else {
    let output: [String: Any] = ["action": actionName, "bundleID": bundleID, "ok": false, "error": "HKAuthorizationStore declares no known setAuthorizationStatuses: spelling", "resolvedTypes": resolvedIdentifiers, "unresolvedTypes": unresolvedIdentifiers]
    printHealthJSON(output, output: sink)
    return 1
  }
  if let sink, set.status == .timedOut {
    sink.write(["action": actionName, "bundleID": bundleID, "ok": false, "error": "Health authorization write timed out", "completionStatus": "timedOut"])
    return 1
  }
  let ok = NSNumber(value: seed.success && set.success ? 1 : 0)
  let seedError = try seed.readErrorValue()
  let setError = try set.readErrorValue()
  let output: [String: Any] = ["action": actionName, "bundleID": bundleID, "ok": ok, "resolvedTypes": resolvedIdentifiers, "unresolvedTypes": unresolvedIdentifiers, "seedError": seedError, "setError": setError]
  printHealthJSON(output, output: sink)
  return (seed.success && set.success) ? 0 : 1
}

private func handleClearAction(client: FBHealthSettingsClient, bundleID: String, sink: BridgeOutput?) throws -> Int {
  let result = try client.clearAuthorization(forBundleIdentifier: bundleID)
  if let sink, result.status == .timedOut {
    sink.write(["action": "clear", "bundleID": bundleID, "ok": false, "error": "Health clear timed out", "completionStatus": "timedOut"])
    return 1
  }
  let ok = NSNumber(value: result.success)
  let clearError = try result.readErrorValue()

  let output: [String: Any] = ["action": "clear", "bundleID": bundleID, "ok": ok, "error": clearError]
  printHealthJSON(output, output: sink)
  return result.success ? 0 : 1
}

private func handleListAction(client: FBHealthSettingsClient, bundleID: String, sink: BridgeOutput?) throws -> Int {
  let result = try client.fetchRecords(forBundleIdentifier: bundleID)
  if let sink, result.status == .timedOut {
    sink.write(["action": "list", "bundleID": bundleID, "ok": false, "error": "Health list timed out", "completionStatus": "timedOut"])
    return 1
  }
  let records = try result.readRecords()

  var recordDicts: [Any] = []
  for record in records {
    recordDicts.append(recordToDictionary(record: record))
  }
  let ok = NSNumber(value: result.hasError ? 0 : 1)
  let fetchError = try result.readErrorValue()
  let output: [String: Any] = ["action": "list", "bundleID": bundleID, "ok": ok, "error": fetchError, "records": recordDicts]
  printHealthJSON(output, output: sink)
  return !result.hasError ? 0 : 1
}

// MARK: - Dispatch

private func handleHealthSettingsActionImpl(
  action: String,
  bundleID: String?,
  typeIdentifiers: [String],
  sink: BridgeOutput?
) throws -> Int {
  let client = FBHealthSettingsClient.live()
  guard let client else {
    return 1
  }
  guard let bundleID else {
    NSLog("[Health] bundleID is required for action '%@'", action)
    return 1
  }
  if action == "list" {
    return try handleListAction(client: client, bundleID: bundleID, sink: sink)
  }
  if action == "clear" {
    return try handleClearAction(client: client, bundleID: bundleID, sink: sink)
  }
  if action == "approve" {
    return try handleSetAction(
      client: client,
      bundleID: bundleID,
      typeIdentifiers: typeIdentifiers,
      statusCode: healthInternalAuthShareAndRead,
      actionName: "approve",
      sink: sink
    )
  }
  if action == "revoke" {
    return try handleSetAction(
      client: client,
      bundleID: bundleID,
      typeIdentifiers: typeIdentifiers,
      statusCode: healthInternalAuthShareAndReadDenied,
      actionName: "revoke",
      sink: sink
    )
  }
  NSLog("[Health] Unknown action '%@'. Supported: list, clear, approve, revoke", action)
  return 1
}

@objc public final class HealthSettingsServiceStaticFuncs: NSObject {

  @objc(handleHealthSettingsAction:bundleID:typeIdentifiers:)
  public static func handleHealthSettingsAction(
    action: String,
    bundleID: String?,
    typeIdentifiers: [String]
  ) -> Int {
    handleHealthSettingsAction(action: action, bundleID: bundleID, typeIdentifiers: typeIdentifiers, output: nil)
  }

  static func handleHealthSettingsAction(action: String, bundleID: String?, typeIdentifiers: [String], output: BridgeOutput?) -> Int {
    do {
      return try handleHealthSettingsActionImpl(action: action, bundleID: bundleID, typeIdentifiers: typeIdentifiers, sink: output)
    } catch {
      return 1
    }
  }
}
#endif
