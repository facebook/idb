/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
// Matches the existing XCTest-based FBSimulatorControl unit suite (FBSimulatorIndigoHIDTests et al.).
// ast-grep-ignore: swift-testing/swift/no-new-xctest
import XCTest

/// Coverage of the guest's audio settings file — the only host-visible representation of the
/// simulated device's volume. The values here are the real shape written by `CoreSimulatorBridge`;
/// the percentages are the ones a hardware volume button actually produces (sixteenths of 100).
final class FBSimulatorAudioSettingsTests: XCTestCase {

  // MARK: - Helpers

  private func write(_ plist: [String: Any]) throws -> String {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("audio-settings-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("audiosettings.plist")
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: path)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return path.path
  }

  private func settings(_ plist: [String: Any]) throws -> FBSimulatorAudioSettings {
    try FBSimulatorAudioSettings.settings(fromPropertyList: plist)
  }

  // MARK: - Parsing

  // The file stores a percentage; callers get 0...1, matching what a guest app reads back from
  // `AVAudioSession.outputVolume`.
  func testVolumeIsReportedAsAFraction() throws {
    XCTAssertEqual(try settings(["sim_volume": 0]).volume, 0, accuracy: 1e-9)
    XCTAssertEqual(try settings(["sim_volume": 60]).volume, 0.6, accuracy: 1e-9)
    XCTAssertEqual(try settings(["sim_volume": 100]).volume, 1, accuracy: 1e-9)
  }

  // The values a real device actually lands on: SpringBoard steps the level by a sixteenth per press
  // and rounds the published percentage, so these are the observed readings, not tidy ones.
  func testTheStepValuesAHardwareButtonProduces() throws {
    XCTAssertEqual(try settings(["sim_volume": 6]).volume, 0.06, accuracy: 1e-9)
    XCTAssertEqual(try settings(["sim_volume": 31]).volume, 0.31, accuracy: 1e-9)
    XCTAssertEqual(try settings(["sim_volume": 87]).volume, 0.87, accuracy: 1e-9)
  }

  // A file written by something other than the guest could carry anything; the reported volume is
  // still a volume.
  func testVolumeIsClampedToTheUnitRange() throws {
    XCTAssertEqual(try settings(["sim_volume": 250]).volume, 1, accuracy: 1e-9)
    XCTAssertEqual(try settings(["sim_volume": -40]).volume, 0, accuracy: 1e-9)
  }

  func testRingerStateIsRead() throws {
    XCTAssertTrue(try settings(["sim_volume": 60, "sim_ringer_state": 1]).ringerEnabled)
    XCTAssertFalse(try settings(["sim_volume": 60, "sim_ringer_state": 0]).ringerEnabled)
  }

  // The ringer key only appears once something has set it, and the ringer is unmuted until then.
  func testRingerDefaultsToEnabledWhenAbsent() throws {
    XCTAssertTrue(try settings(["sim_volume": 60]).ringerEnabled)
  }

  // Every value this could default to is itself a plausible volume, so a caller checking whether a
  // button press moved the level must not be handed an invented one.
  func testAMissingVolumeIsAnErrorRatherThanADefault() {
    XCTAssertThrowsError(try settings(["sim_ringer_state": 1])) { error in
      guard case let FBSimulatorAudioError.volumeMissing(keys) = error else {
        return XCTFail("expected volumeMissing, got \(error)")
      }
      XCTAssertEqual(keys, ["sim_ringer_state"], "the error names what the file did carry")
    }
  }

  func testANonNumericVolumeIsAnError() {
    XCTAssertThrowsError(try settings(["sim_volume": "loud"]))
  }

  // MARK: - Reading the file

  // The full shape `CoreSimulatorBridge` writes, so a change to the real file's other keys does not
  // break the read.
  func testReadsTheFileTheGuestActuallyWrites() throws {
    let path = try write([
      "sim_input_device_uid": "BuiltInMicrophoneDevice",
      "sim_output_device_uid": "BuiltInSpeakerDevice",
      "sim_ringer_state": 1,
      "sim_volume": 37,
    ])
    let settings = try FBSimulatorAudioSettings.settings(atPath: path)
    XCTAssertEqual(settings.volume, 0.37, accuracy: 1e-9)
    XCTAssertTrue(settings.ringerEnabled)
  }

  // The guest writes this file while booting, so its absence is the normal state of a simulator that
  // has never been booted — the error says so rather than reporting a volume of zero.
  func testAMissingFileIsReportedAsUnreadable() {
    let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("no-such-audiosettings.plist")
    XCTAssertThrowsError(try FBSimulatorAudioSettings.settings(atPath: path)) { error in
      guard case FBSimulatorAudioError.unreadable = error else {
        return XCTFail("expected unreadable, got \(error)")
      }
      XCTAssertTrue(
        error.localizedDescription.contains("never booted"),
        "the message should explain the common cause, got: \(error.localizedDescription)")
    }
  }

  func testANonPropertyListFileIsReportedAsMalformed() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("audio-settings-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("audiosettings.plist")
    try Data("not a plist".utf8).write(to: path)

    XCTAssertThrowsError(try FBSimulatorAudioSettings.settings(atPath: path.path)) { error in
      guard case FBSimulatorAudioError.malformed = error else {
        return XCTFail("expected malformed, got \(error)")
      }
    }
  }

  // MARK: - Location

  // The guest reaches the same file through SIMULATOR_AUDIO_SETTINGS_PATH; the host has to build it
  // from the device's data directory, so the relative path is part of the contract.
  func testTheSettingsPathIsRelativeToTheDataDirectory() {
    XCTAssertEqual(FBSimulatorAudioSettings.relativePath, "var/run/simulatoraudio/audiosettings.plist")
  }
}
