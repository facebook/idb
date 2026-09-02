/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let mobileBackupDomain = "com.apple.mobile.backup"

/// Taking a single device into and out of use: connecting, pairing, and opening a session.
///
/// Separate from `FBAMDeviceManager`, which discovers the *set* of devices. These operate on one
/// device and are what `FBAMDevice` wraps around every operation it performs.
@objc(FBAMDeviceUsage)
public final class FBAMDeviceUsage: NSObject {

  /// Connects to the device and opens a session on it, pairing first if required.
  @objc(startUsing:calls:logger:error:)
  public class func start(using device: AMDevice, calls: AMDCalls, logger: any FBControlCoreLogger) throws {
    // Connect first
    try startConnection(to: device, calls: calls, logger: logger)
    // Confirm pairing and start a session
    try startSessionByPairing(with: device, calls: calls, logger: logger)
    logger.log("\(device) ready for use")
  }

  /// Ends the session and then the connection. Failures are logged by the callees rather than
  /// surfaced: there is nothing a caller can do about a teardown that did not take.
  @objc(stopUsing:calls:logger:error:)
  public class func stop(using device: AMDevice, calls: AMDCalls, logger: any FBControlCoreLogger) throws {
    // Stop the session first.
    try? stopSession(with: device, calls: calls, logger: logger)
    // Then the connection.
    try? stopConnection(to: device, calls: calls, logger: logger)
  }

  // MARK: - Steps

  internal class func startConnection(
    to device: AMDevice,
    calls: AMDCalls,
    logger: any FBControlCoreLogger
  ) throws {
    logger.log("Connecting to \(device)")
    let status = calls.Connect(device)
    guard status == 0 else {
      throw FBAMDeviceManagerError.connectFailed(device: "\(device)", message: errorText(status, calls: calls))
    }
  }

  internal class func startSessionByPairing(
    with device: AMDevice,
    calls: AMDCalls,
    logger: any FBControlCoreLogger
  ) throws {
    // Then confirm the pairing.
    logger.log("Checking whether \(device) is paired")
    if calls.IsPaired(device) == 0 {
      logger.log("\(device) is not paired, attempting to pair")
      let status = calls.Pair(device)
      guard status == 0 else {
        throw FBAMDeviceManagerError.notPaired(device: "\(device)", message: errorText(status, calls: calls))
      }
      logger.log("\(device) succeeded pairing request")
    }

    logger.log("Validating Pairing to \(device)")
    let validateStatus = calls.ValidatePairing(device)
    guard validateStatus == 0 else {
      throw FBAMDeviceManagerError.pairingValidationFailed(
        device: "\(device)", message: errorText(validateStatus, calls: calls))
    }

    // A session may also be required.
    logger.log("Starting Session on \(device)")
    let sessionStatus = calls.StartSession(device)
    guard sessionStatus == 0 else {
      _ = calls.Disconnect(device)
      throw FBAMDeviceManagerError.sessionFailed(message: errorText(sessionStatus, calls: calls))
    }
  }

  internal class func stopSession(
    with device: AMDevice,
    calls: AMDCalls,
    logger: any FBControlCoreLogger
  ) throws {
    logger.log("Stopping Session on \(device)")
    _ = calls.StopSession(device)
  }

  internal class func stopConnection(
    to device: AMDevice,
    calls: AMDCalls,
    logger: any FBControlCoreLogger
  ) throws {
    logger.log("Disconnecting from \(device)")
    _ = calls.Disconnect(device)
    logger.log("Disconnected from \(device)")
  }

  internal class func obtainDeviceValues(_ device: AMDevice, calls: AMDCalls) -> [String: Any]? {
    // Get the values from the default domain, this will obtain information regardless of whether
    // pairing was successful or not.
    guard var info = calls.CopyValue(device, nil, nil)?.takeRetainedValue() as? [String: Any] else {
      return nil
    }

    // Synthetic Values.
    info[FBDeviceKey.isPaired.rawValue] = calls.IsPaired(device) != 0

    // Get values from mobile backup, this will only return meaningful information if paired.
    let backupInfo =
      calls.CopyValue(device, mobileBackupDomain as CFString, nil)?.takeRetainedValue() as? [String: Any] ?? [:]
    // Insert the values from subdomains.
    info[mobileBackupDomain] = backupInfo

    return info
  }

  private class func errorText(_ status: Int32, calls: AMDCalls) -> String {
    calls.CopyErrorText(status)?.takeRetainedValue() as String? ?? "Unknown error"
  }

}
