/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
import FBControlCore
import Foundation

@objc public protocol FBSimulatorMediaCommandsProtocol: NSObjectProtocol, FBiOSTargetCommand {
  @objc(addMedia:)
  func addMedia(_ mediaFileURLs: [URL]) -> FBFuture<NSNull>
}

@objc(FBSimulatorMediaCommands)
public final class FBSimulatorMediaCommands: NSObject, FBSimulatorMediaCommandsProtocol {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorMediaCommands {
    return FBSimulatorMediaCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - FBSimulatorMediaCommands Protocol

  @objc
  public func addMedia(_ mediaFileURLs: [URL]) -> FBFuture<NSNull> {
    do {
      try uploadMedia(mediaFileURLs)
      return FBFuture<NSNull>.empty()
    } catch {
      return FBFuture(error: error)
    }
  }

  // MARK: - Private

  private class var predicateForVideoPaths: NSPredicate {
    return predicateForPaths(matchingUTIs: [kUTTypeMovie as String, kUTTypeMPEG4 as String, kUTTypeQuickTimeMovie as String])
  }

  private class var predicateForPhotoPaths: NSPredicate {
    return predicateForPaths(matchingUTIs: [kUTTypeImage as String, kUTTypePNG as String, kUTTypeJPEG as String, kUTTypeJPEG2000 as String])
  }

  private class var predicateForContactPaths: NSPredicate {
    return predicateForPaths(matchingUTIs: [kUTTypeVCard as String])
  }

  private class var predicateForMediaPaths: NSPredicate {
    return NSCompoundPredicate(orPredicateWithSubpredicates: [
      predicateForVideoPaths,
      predicateForPhotoPaths,
      predicateForContactPaths,
    ])
  }

  private func uploadMedia(_ mediaFileURLs: [URL]) throws {
    guard let simulator = self.simulator else {
      throw FBSimulatorError.describe("Simulator deallocated").build()
    }

    if mediaFileURLs.isEmpty {
      throw FBSimulatorError.describe("Cannot upload media, none was provided").build()
    }

    let unknown = (mediaFileURLs as NSArray).filtered(using: NSCompoundPredicate(notPredicateWithSubpredicate: FBSimulatorMediaCommands.predicateForMediaPaths)) as! [URL]
    if !unknown.isEmpty {
      throw FBSimulatorError.describe("\(unknown) not a known media path").build()
    }

    if simulator.state != .booted {
      let stateString = FBSimDeviceWrapper.stateString(forDevice: simulator.device) ?? "unknown"
      throw FBSimulatorError.describe("Simulator must be booted to upload photos, is \(stateString)").build()
    }

    let photos = (mediaFileURLs as NSArray).filtered(using: FBSimulatorMediaCommands.predicateForPhotoPaths) as! [URL]
    for url in photos {
      do {
        try FBSimDeviceWrapper.addPhoto(onDevice: simulator.device, url: url)
      } catch {
        throw FBSimulatorError.describe("Failed to add photo \(url)").caused(by: error as NSError).build()
      }
    }

    let videos = (mediaFileURLs as NSArray).filtered(using: FBSimulatorMediaCommands.predicateForVideoPaths) as! [URL]
    for url in videos {
      do {
        try FBSimDeviceWrapper.addVideo(onDevice: simulator.device, url: url)
      } catch {
        throw FBSimulatorError.describe("Failed to add video \(url)").caused(by: error as NSError).build()
      }
    }

    let contacts = (mediaFileURLs as NSArray).filtered(using: FBSimulatorMediaCommands.predicateForContactPaths) as! [URL]
    if !contacts.isEmpty {
      do {
        try FBSimDeviceWrapper.addMedia(onDevice: simulator.device, urls: contacts)
      } catch {
        throw FBSimulatorError.describe("Failed to add contacts \(contacts)").caused(by: error as NSError).build()
      }
    }
  }

  private class func predicateForPaths(matchingUTIs utis: [String]) -> NSPredicate {
    let utiSet = Set(utis)
    let workspace = NSWorkspace.shared
    return NSPredicate { (evaluatedObject: Any?, _: [String: Any]?) -> Bool in
      guard let url = evaluatedObject as? URL else { return false }
      guard let uti = try? workspace.type(ofFile: url.path) else { return false }
      return utiSet.contains(uti)
    }
  }
}
