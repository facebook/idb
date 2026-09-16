/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import ArgumentParser
@_implementationOnly import FBControlCore
@_implementationOnly import FBSimulatorControl
import Foundation
@_implementationOnly import SimulatorVideo

struct SimulatorOptions: ParsableArguments {
  @Option(help: "Simulator device set path") var set: String
  @Option(help: "Booted simulator UDID") var udid: String

  @MainActor
  func simulator(logger: any FBControlCoreLogger) throws -> FBSimulator {
    let configuration = FBSimulatorControlConfiguration(deviceSetPath: set, logger: logger)
    let control = try SimulatorControlBootstrap.withConfiguration(configuration)
    guard let simulator = control.set.simulator(withUDID: udid) else {
      throw ValidationError("No simulator \(udid) in \(set)")
    }
    guard simulator.state == .booted else {
      throw ValidationError("Simulator \(udid) is not booted")
    }
    return simulator
  }
}

struct VideoOptions: ParsableArguments {
  @Option(help: "Frames per second; omitted or 0 follows screen and overlay updates") var fps: UInt?
  @Option(help: "Scale factor between 0 and 1") var scale: Double?
  @Option(help: "Compression quality between 0 and 1") var compressionQuality: Double?
  @Option(help: "Average bitrate in bits per second") var avgBitrate: UInt?
  @Option(help: "Key frame interval in seconds") var keyFrameRate: Double?
  @Option(help: "Directory for composited screenshots") var screenshotDir: String?
  @Option(name: .customLong("bar"), parsing: .upToNextOption, help: "Bar position[:size][:pad|overlay]; default size is 24") var bars: [String] = []
  @Option(name: .customLong("bar-stats"), parsing: .upToNextOption, help: "Bar positions showing encoder statistics") var barStats: [String] = []
  @Option(help: "Overlay coordinates: composed or device") var overlayCoordSpace: String = "composed"

  func validate() throws {
    guard compressionQuality == nil || avgBitrate == nil else {
      throw ValidationError("--compression-quality and --avg-bitrate are mutually exclusive")
    }
    if let scale, !scale.isFinite || scale <= 0 || scale > 1 {
      throw ValidationError("--scale must be greater than zero and at most one")
    }
    if let fps, fps > UInt(Int.max) {
      throw ValidationError("--fps is too large")
    }
    if let compressionQuality, !compressionQuality.isFinite || !(0...1).contains(compressionQuality) {
      throw ValidationError("--compression-quality must be between zero and one")
    }
    if let avgBitrate, avgBitrate == 0 || avgBitrate > UInt(Int.max) {
      throw ValidationError("--avg-bitrate must be a positive integer")
    }
    if let keyFrameRate, !keyFrameRate.isFinite || keyFrameRate <= 0 {
      throw ValidationError("--key-frame-rate must be positive")
    }
    guard OverlayCoordSpace(rawValue: overlayCoordSpace) != nil else {
      throw ValidationError("--overlay-coord-space must be composed or device")
    }
    for bar in bars {
      let parts = bar.split(separator: ":", omittingEmptySubsequences: false)
      guard parts.count <= 3, let position = parts.first,
        ["top", "bottom", "left", "right"].contains(String(position)),
        parts.dropFirst().allSatisfy({ part in
          if let size = Int(part) { return size > 0 && size <= 4096 }
          return ["pad", "overlay"].contains(String(part))
        })
      else { throw ValidationError("Invalid --bar value: \(bar)") }
    }
  }

  func configuration(format: VideoStreamFormat) -> VideoStreamConfiguration {
    let rateControl: VideoStreamRateControl?
    if let compressionQuality {
      rateControl = .quality(compressionQuality)
    } else if let avgBitrate {
      rateControl = .bitrate(Int(avgBitrate))
    } else {
      rateControl = nil
    }
    return VideoStreamConfiguration(format: format, framesPerSecond: fps.map { Int($0) }, rateControl: rateControl, scaleFactor: scale, keyFrameRate: keyFrameRate)
  }

  @MainActor
  func composition(simulator: FBSimulator, logger: any FBControlCoreLogger) throws -> (VideoStreamEdgeInsets, OverlayRenderer, [(position: String, height: Int, mode: BarMode)]) {
    if let screenshotDir { try FileManager.default.createDirectory(atPath: screenshotDir, withIntermediateDirectories: true) }
    let resolved = VideoBars(bars: bars, barStats: barStats).resolve(deprecatedBottomStatusBar: false, deprecatedTopStatusBar: false, logger: logger)
    let overlay = simulator.prepareVideoOverlay(edgeInsets: resolved.edgeInsets, scaleFactor: scale, overlayCoordSpace: OverlayCoordSpace(rawValue: overlayCoordSpace) ?? .composed)
    return (overlay.scaledInsets, overlay.renderer, resolved.parsedBars)
  }
}
