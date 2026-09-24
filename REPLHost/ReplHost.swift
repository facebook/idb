/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AVFoundation
import Contacts
import Photos
import SwiftUI

@main
struct ReplHost: App {
  var body: some Scene {
    WindowGroup {
      if AccessibilityFixture.isRequested {
        AccessibilityFixture()
          .ignoresSafeArea()
      } else {
        ContentView()
      }
    }
  }
}

/// A privacy-gated service the host can ask for on demand.
///
/// TCC authorization is scoped to the requesting client, so it is only
/// observable from a process running as this bundle id. A caller that
/// pre-approves a service from outside the container -- `SimulatorFrameworkBridge`
/// -- can confirm the approval landed only by having the app itself ask.
private enum PrivacyService: String, CaseIterable, Identifiable {
  case camera
  case microphone
  case photos
  case contacts

  var id: String { rawValue }

  var title: String { "Request \(rawValue.capitalized)" }

  var requestIdentifier: String { "request-\(rawValue)" }

  func request() async -> PrivacyResult {
    switch self {
    case .camera:
      return await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
    case .microphone:
      return await AVCaptureDevice.requestAccess(for: .audio) ? .authorized : .denied
    case .photos:
      return PrivacyResult(await PHPhotoLibrary.requestAuthorization(for: .readWrite))
    case .contacts:
      do {
        return try await CNContactStore().requestAccess(for: .contacts) ? .authorized : .denied
      } catch {
        return .failed
      }
    }
  }
}

private enum PrivacyResult: String {
  case authorized
  case limited
  case denied
  case undetermined
  case failed

  /// Photos distinguishes full access from limited selection, and the two are
  /// separate TCC authorization values rather than degrees of one.
  init(_ status: PHAuthorizationStatus) {
    switch status {
    case .authorized: self = .authorized
    case .limited: self = .limited
    case .denied, .restricted: self = .denied
    case .notDetermined: self = .undetermined
    @unknown default: self = .failed
    }
  }
}

struct ContentView: View {
  private static let idleMarker = "privacy-result-idle"

  @State private var marker = ContentView.idleMarker

  var body: some View {
    VStack(spacing: 16) {
      ForEach(PrivacyService.allCases) { service in
        Button(service.title) {
          Task { marker = await Self.marker(for: service) }
        }
        .accessibilityIdentifier(service.requestIdentifier)
      }
      // Identifier and label carry the same text so a marker match works on
      // either key, and a failure screenshot shows the state that was waited on.
      Text(marker)
        .accessibilityIdentifier(marker)
    }
  }

  private static func marker(for service: PrivacyService) async -> String {
    "privacy-result-\(service.rawValue)-\(await service.request().rawValue)"
  }
}
