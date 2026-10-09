/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The assistive client an accessibility translator request says it comes from: the value of
/// `-[AXPTranslatorRequest clientType]`. Raw values are the integers the translator carries.
///
/// On macOS the translator fills this in from the identity of the AX client whose request it is servicing,
/// so inside Simulator.app it names the real client (VoiceOver, Accessibility Inspector, an XCTest run).
/// A process that is not servicing an incoming AX request — idb — gets `noClient`. Inside the simulator, the
/// translator maps it to a `BridgeAXRequestingClient` for the duration of the request, and the target
/// application answers for that client: which children it reports, and which elements, traits and values
/// it exposes.
///
/// The mapping is the same on every runtime from iOS 26.4 to iOS 27.0.
public enum BridgeAXClientType: UInt64, Sendable, CaseIterable {
  /// No AX request is being serviced. What idb's host translator sends.
  case noClient = 0
  /// An AX request from a client the translator could not identify.
  case unidentified = 1
  /// Any client with a bundle identifier not named below.
  case application = 2
  /// `com.apple.dt.Xcode-Helper`.
  case xcodeHelper = 3
  /// `com.apple.xctest`.
  case xctest = 4
  /// `com.apple.scripter`.
  case scripter = 5
  /// `com.apple.systemevents`.
  case systemEvents = 6
  /// `com.apple.VoiceOver`. The only client served the attributed value description.
  case voiceOver = 7
  /// `com.apple.inputmethod.AssistiveControl`.
  case switchControl = 8
  /// `com.apple.KeyboardAccessAgent`.
  case fullKeyboardAccess = 9
  /// `com.apple.inputmethod.ironwood`.
  case voiceControl = 10
  /// An unidentified client while "show all objects" is enabled for accessibility, as Accessibility
  /// Inspector does.
  case accessibilityInspector = 11

  /// The client the target application sees for this request. Values outside `application` through
  /// `accessibilityInspector` reach it as no client at all.
  public var requestingClient: BridgeAXRequestingClient {
    switch self {
    case .noClient, .unidentified: .noClient
    case .application, .scripter, .systemEvents: .scripting
    case .xcodeHelper, .xctest: .xctest
    case .voiceOver: .voiceOver
    case .switchControl: .assistiveTouch
    case .fullKeyboardAccess: .fullKeyboardAccess
    case .voiceControl: .voiceControl
    case .accessibilityInspector: .audit
    }
  }

  /// Whether the target application answers this client with its automation tree — the children an
  /// application sets in `automationElements`, falling back to the ones XCTest reads — rather than the
  /// flattened, labelled leaves VoiceOver reads.
  ///
  /// The automation tree costs roughly an order of magnitude more translator round trips, is not a
  /// superset of the VoiceOver tree, and its granularity also depends on the device's `AutomationEnabled`
  /// accessibility preference. An application that stores `automationElements` serves them as stored,
  /// whatever is on screen.
  public var deservesAutomation: Bool {
    requestingClient.deservesAutomation
  }
}

/// The requesting client an application's accessibility runtime answers for: iOS's `AXRequestingClient`.
/// Raw values are the integers the runtime uses. Only some are reachable from a `BridgeAXClientType`. The
/// runtime assigns the rest to in-guest processes by process name, or a process overrides its own. Nothing
/// in the simulator runtime produces 9, so it has no case.
public enum BridgeAXRequestingClient: UInt32, Sendable, CaseIterable {
  case noClient = 0
  /// `scripter2`, `uiautomationd`, `uia2unboxed`.
  case scripting = 1
  /// `testmanagerd`.
  case xctest = 2
  /// `vot`.
  case voiceOver = 3
  /// `assistivetouchd`.
  case assistiveTouch = 4
  /// `CommandAndControl`.
  case voiceControl = 5
  /// `SketchBoard`.
  case sketchBoard = 6
  /// A request from the application's own process.
  case inProcess = 7
  /// `Typist`.
  case typist = 8
  /// `FullKeyboardAccess`.
  case fullKeyboardAccess = 10
  /// Speak Screen, which reads the screen forward element by element.
  case speakScreen = 11
  /// `axauditd`.
  case audit = 12
  /// `axctl`.
  case axctl = 13
  /// `WatchControl`.
  case watchControl = 14
  /// Hover Text.
  case hoverText = 15
  /// `ScreenContinuityShell` (iPhone Mirroring).
  case iPhoneMirroring = 16
  /// The Switch Control scanner.
  case switchControlScanner = 17

  /// Whether the application answers this client with its automation tree. `inProcess` gets it only while
  /// the device's `AutomationEnabled` accessibility preference is on, and is reported as `false` here.
  public var deservesAutomation: Bool {
    switch self {
    case .scripting, .xctest, .typist: true
    case .noClient, .voiceOver, .assistiveTouch, .voiceControl, .sketchBoard, .inProcess, .fullKeyboardAccess, .speakScreen, .audit,
      .axctl,
      .watchControl, .hoverText, .iPhoneMirroring, .switchControlScanner:
      false
    }
  }
}
