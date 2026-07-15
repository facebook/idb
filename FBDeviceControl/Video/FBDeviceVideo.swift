/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import CoreMediaIO
@preconcurrency import FBControlCore
import Foundation

protocol FBDeviceVideoCaptureDeviceCandidate {
  var uniqueID: String { get }
  var localizedName: String { get }
  var modelID: String { get }

  func hasMediaType(_ mediaType: AVMediaType) -> Bool
}

extension AVCaptureDevice: FBDeviceVideoCaptureDeviceCandidate {}

public final class FBDeviceVideo {
  private let encoder: FBVideoFileWriter
  private let workQueue: DispatchQueue

  private static let captureDeviceDiscoveryPollNanoseconds: UInt64 = 250_000_000

  // MARK: Initialization Helpers

  private class func videoCaptureAuthorizationStatusString(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "notDetermined"
    case .restricted:
      return "restricted"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    @unknown default:
      return "unknown(\(status.rawValue))"
    }
  }

  private class func videoCaptureAuthorizationError(_ status: AVAuthorizationStatus) -> Error {
    if status == .denied {
      return FBDeviceControlError.describe(
        "Camera authorization is denied. Grant camera access to the application responsible for idb_companion in System Settings > Privacy & Security > Camera"
      ).build()
    }
    if status == .restricted {
      return FBDeviceControlError.describe("Camera authorization is restricted by system policy").build()
    }
    return FBDeviceControlError.describe(
      "Camera authorization request did not grant access (status: \(videoCaptureAuthorizationStatusString(status)))"
    ).build()
  }

  static func ensureVideoCaptureAuthorization(
    logger: any FBControlCoreLogger,
    authorizationStatus: () -> AVAuthorizationStatus,
    requestAccess: () async -> Bool
  ) async throws {
    let status = authorizationStatus()
    logger.log("[FBDeviceVideo] Camera authorization status: \(videoCaptureAuthorizationStatusString(status))")

    switch status {
    case .authorized:
      return
    case .denied, .restricted:
      throw videoCaptureAuthorizationError(status)
    case .notDetermined:
      let granted = await requestAccess()
      let finalStatus = authorizationStatus()
      logger.log(
        "[FBDeviceVideo] Camera authorization status after request: \(videoCaptureAuthorizationStatusString(finalStatus)) (granted=\(granted ? "YES" : "NO"))"
      )
      guard granted, finalStatus == .authorized else {
        throw videoCaptureAuthorizationError(finalStatus)
      }
    @unknown default:
      throw videoCaptureAuthorizationError(status)
    }
  }

  private class func allowAccessToScreenCaptureDevices() throws {
    var properties = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
    )
    var allow: UInt32 = 1
    let status = CMIOObjectSetPropertyData(
      CMIOObjectID(kCMIOObjectSystemObject),
      &properties,
      0,
      nil,
      UInt32(MemoryLayout<UInt32>.size),
      &allow
    )
    if status != 0 {
      throw FBDeviceControlError.describe("Failed to enable Screen Capture devices with status \(status)").build()
    }
  }

  private class func normalizedIdentifier(_ identifier: String) -> String {
    identifier
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .joined()
      .lowercased()
  }

  static func captureDevice<Candidate: FBDeviceVideoCaptureDeviceCandidate>(
    forUDID targetUDID: String,
    named targetName: String,
    connectedDeviceUDIDs: [String],
    from candidates: [Candidate]
  ) -> Candidate? {
    let normalizedUDID = normalizedIdentifier(targetUDID)
    var screenCandidates: [Candidate] = []
    var identifierMatches: [Candidate] = []
    var nameMatches: [Candidate] = []

    for candidate in candidates {
      guard candidate.modelID == "iOS Device", candidate.hasMediaType(.muxed) else {
        continue
      }
      screenCandidates.append(candidate)

      let normalizedCandidateID = normalizedIdentifier(candidate.uniqueID)
      if !normalizedUDID.isEmpty, normalizedCandidateID.contains(normalizedUDID) {
        identifierMatches.append(candidate)
      }
      if candidate.localizedName == targetName {
        nameMatches.append(candidate)
      }
    }

    if !identifierMatches.isEmpty {
      return identifierMatches.count == 1 ? identifierMatches[0] : nil
    }
    if !nameMatches.isEmpty {
      return nameMatches.count == 1 ? nameMatches[0] : nil
    }
    if screenCandidates.count == 1,
       connectedDeviceUDIDs.count == 1,
       connectedDeviceUDIDs[0] == targetUDID
    {
      return screenCandidates[0]
    }
    return nil
  }

  private class func captureDeviceInventory(_ candidates: [AVCaptureDevice]) -> String {
    let descriptions = candidates.map { candidate in
      var mediaTypes: [String] = []
      if candidate.hasMediaType(.video) {
        mediaTypes.append("video")
      }
      if candidate.hasMediaType(.audio) {
        mediaTypes.append("audio")
      }
      if candidate.hasMediaType(.muxed) {
        mediaTypes.append("muxed")
      }
      return "{name=\(candidate.localizedName), uniqueID=\(candidate.uniqueID), modelID=\(candidate.modelID), deviceType=\(candidate.deviceType.rawValue), mediaTypes=\(mediaTypes.joined(separator: ","))}"
    }.sorted()
    return descriptions.isEmpty ? "<none>" : descriptions.joined(separator: "; ")
  }

  private class func captureDeviceDiscoverySession() -> AVCaptureDevice.DiscoverySession {
    if #available(macOS 14.0, *) {
      return AVCaptureDevice.DiscoverySession(
        deviceTypes: [.external, .continuityCamera],
        mediaType: nil,
        position: .unspecified
      )
    }
    return AVCaptureDevice.DiscoverySession(
      deviceTypes: [.externalUnknown],
      mediaType: nil,
      position: .unspecified
    )
  }

  private class func findCaptureDeviceAsync(for device: FBDevice) async throws -> AVCaptureDevice {
    let timeout = FBControlCoreGlobalConfiguration.fastTimeout
    let deadline = Date().addingTimeInterval(timeout)
    let logger = device.logger ?? FBControlCoreGlobalConfiguration.defaultLogger
    var discoverySession: AVCaptureDevice.DiscoverySession?
    var lastInventory: String?

    while true {
      if let captureDevice = AVCaptureDevice(uniqueID: device.udid) {
        return captureDevice
      }

      if discoverySession == nil {
        discoverySession = captureDeviceDiscoverySession()
      }
      let candidates = discoverySession?.devices ?? []
      let inventory = captureDeviceInventory(candidates)
      if inventory != lastInventory {
        logger.log("[FBDeviceVideo] Capture device candidates: \(inventory)")
        lastInventory = inventory
      }

      let connectedDeviceUDIDs = device.set?.allDevices.map(\.udid) ?? []
      if let captureDevice = captureDevice(
        forUDID: device.udid,
        named: device.name,
        connectedDeviceUDIDs: connectedDeviceUDIDs,
        from: candidates
      ) {
        logger.log(
          "[FBDeviceVideo] Matched screen capture device name=\(captureDevice.localizedName) uniqueID=\(captureDevice.uniqueID) modelID=\(captureDevice.modelID)"
        )
        return captureDevice
      }

      if Date() >= deadline {
        throw FBDeviceControlError.describe("Timed out waiting \(timeout)s for device \(device) to have an associated capture device appear").build()
      }
      try await Task.sleep(nanoseconds: captureDeviceDiscoveryPollNanoseconds)
    }
  }

  // MARK: Initializers

  public class func captureSessionAsync(for device: FBDevice) async throws -> AVCaptureSession {
    try await captureSessionAsync(
      logger: device.logger ?? FBControlCoreGlobalConfiguration.defaultLogger,
      authorizationStatus: {
        AVCaptureDevice.authorizationStatus(for: .video)
      },
      requestAccess: {
        await AVCaptureDevice.requestAccess(for: .video)
      },
      allowAccessToScreenCaptureDevices: {
        try allowAccessToScreenCaptureDevices()
      },
      findCaptureDevice: {
        try await findCaptureDeviceAsync(for: device)
      }
    )
  }

  static func captureSessionAsync(
    logger: any FBControlCoreLogger,
    authorizationStatus: () -> AVAuthorizationStatus,
    requestAccess: () async -> Bool,
    allowAccessToScreenCaptureDevices: () throws -> Void,
    findCaptureDevice: () async throws -> AVCaptureDevice
  ) async throws -> AVCaptureSession {
    try await ensureVideoCaptureAuthorization(
      logger: logger,
      authorizationStatus: authorizationStatus,
      requestAccess: requestAccess
    )
    try allowAccessToScreenCaptureDevices()
    let captureDevice = try await findCaptureDevice()
    let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
    let session = AVCaptureSession()
    if !session.canAddInput(deviceInput) {
      throw FBDeviceControlError.describe("Cannot add Device Input to session for \(captureDevice)").build()
    }
    session.addInput(deviceInput)
    return session
  }

  public class func videoAsync(for device: FBDevice, filePath: String) async throws -> FBDeviceVideo {
    let session = try await captureSessionAsync(for: device)
    let encoder = try FBVideoFileWriter.writer(withSession: session, filePath: filePath, logger: device.logger ?? FBControlCoreGlobalConfiguration.defaultLogger)
    return FBDeviceVideo(encoder: encoder, workQueue: device.workQueue)
  }

  private init(encoder: FBVideoFileWriter, workQueue: DispatchQueue) {
    self.encoder = encoder
    self.workQueue = workQueue
  }

  // MARK: Public

  public func startRecording() -> FBFuture<NSNull> {
    encoder.startRecording()
  }

  public func stopRecording() -> FBFuture<NSNull> {
    encoder.stopRecording()
  }
}
