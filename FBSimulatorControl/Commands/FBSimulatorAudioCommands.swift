/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Foundation

/**
 The simulated device's audio settings, as its apps and the host audio device see them.

 The guest owns this. `SBVolumeControl` holds the level in memory and, whenever it changes, publishes
 it as an integer percentage on the `com.apple.springboard.volumestate` Darwin notification;
 `CoreSimulatorBridge` observes that and writes the value into the settings file. A guest app's
 `AVAudioSession.outputVolume` reads the same number back, and the host CoreAudio process-volume
 scalar is set from it — so this file, and no preferences domain, is where the device's volume is
 observable from.

 That makes it the only way to see the volume from the host, and so the only way to check that a
 hardware volume-button press did anything.

 Two consequences of the guest's bookkeeping are worth knowing, because they are surprising:

 - **It is a mirror, not the source of truth.** SpringBoard publishes to the file and never reads it
   back. Writing to it does not move SpringBoard's own level, and the next button press overwrites it
   from that untouched level.
 - **It resets to 60 when SpringBoard restarts**, because `SBVolumeControl` initialises its level to
   `0.6` and only publishes on a change.
 */
public struct FBSimulatorAudioSettings: Equatable, Sendable {

  /// Path of the settings file, relative to the simulator's data directory. The guest reaches the
  /// same file through its `SIMULATOR_AUDIO_SETTINGS_PATH` environment variable.
  public static let relativePath = "var/run/simulatoraudio/audiosettings.plist"

  /// The output volume, `0...1`. Stored in the file as an integer percentage; one hardware
  /// volume-button press moves it a sixteenth — 6.25 points — and the guest clamps at both ends.
  public let volume: Double

  /// Whether the ringer is unmuted.
  public let ringerEnabled: Bool

  public init(volume: Double, ringerEnabled: Bool) {
    self.volume = volume
    self.ringerEnabled = ringerEnabled
  }

  /// Parses the settings from the file's deserialized contents.
  ///
  /// A missing or non-numeric `sim_volume` is an error rather than a default. Every value this could
  /// substitute — 0, 0.6, 1 — is itself a plausible real volume, so a default would be indistinguishable
  /// from a reading, and a caller checking whether a button press moved the level would be told a
  /// number the device is not at. `sim_ringer_state` does default, to enabled, because the ringer is
  /// unmuted until something mutes it.
  public static func settings(fromPropertyList plist: [String: Any]) throws -> FBSimulatorAudioSettings {
    guard let percentage = plist["sim_volume"] as? NSNumber else {
      throw FBSimulatorAudioError.volumeMissing(keys: plist.keys.sorted())
    }
    return FBSimulatorAudioSettings(
      volume: min(max(percentage.doubleValue / 100, 0), 1),
      ringerEnabled: (plist["sim_ringer_state"] as? NSNumber)?.boolValue ?? true)
  }

  /// Reads and parses the settings file at `path`.
  public static func settings(atPath path: String) throws -> FBSimulatorAudioSettings {
    let data: Data
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: path))
    } catch {
      throw FBSimulatorAudioError.unreadable(path: path, underlying: error)
    }
    let deserialized = try? PropertyListSerialization.propertyList(from: data, format: nil)
    guard let plist = deserialized as? [String: Any] else {
      throw FBSimulatorAudioError.malformed(path: path)
    }
    return try settings(fromPropertyList: plist)
  }
}

/// The failures of reading the simulated device's audio settings.
public enum FBSimulatorAudioError: Error, LocalizedError {
  /// The simulator reported no data directory to look in.
  case noDataDirectory
  /// The settings file could not be read. The guest writes it while booting, so it is absent on a
  /// simulator that has never been booted.
  case unreadable(path: String, underlying: Error)
  /// The file is not a property list dictionary.
  case malformed(path: String)
  /// The file parsed but carries no volume.
  case volumeMissing(keys: [String])

  public var errorDescription: String? {
    switch self {
    case .noDataDirectory:
      return "The simulator reported no data directory, so its audio settings cannot be located"
    case let .unreadable(path, underlying):
      return
        "Could not read the simulator's audio settings at \(path): \(underlying.localizedDescription). The guest writes this file while booting, so it is absent on a simulator that has never booted."
    case let .malformed(path):
      return "The simulator's audio settings at \(path) are not a property list dictionary"
    case let .volumeMissing(keys):
      let present = keys.isEmpty ? "none" : keys.joined(separator: ", ")
      return "The simulator's audio settings carry no sim_volume; keys present: \(present)"
    }
  }
}

// MARK: - AudioCommands

extension FBSimulator: AudioCommands {

  /// The path of this simulator's audio settings file.
  var audioSettingsPath: String? {
    dataDirectory.map { ($0 as NSString).appendingPathComponent(FBSimulatorAudioSettings.relativePath) }
  }

  public func audioSettings() async throws -> FBSimulatorAudioSettings {
    guard let path = audioSettingsPath else {
      throw FBSimulatorAudioError.noDataDirectory
    }
    return try FBSimulatorAudioSettings.settings(atPath: path)
  }
}
