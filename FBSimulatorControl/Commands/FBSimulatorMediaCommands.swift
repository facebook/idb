/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
@preconcurrency import CoreSimulator
import FBControlCore
import Foundation
import UniformTypeIdentifiers

// swiftlint:disable force_cast

@objc(FBSimulatorMediaCommands)
public final class FBSimulatorMediaCommands: NSObject, FBiOSTargetCommand {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  @objc(commandsWithTarget:)
  public class func commands(with target: any FBiOSTarget) -> FBSimulatorMediaCommands {
    FBSimulatorMediaCommands(simulator: target as! FBSimulator)
  }

  private init(simulator: FBSimulator) {
    self.simulator = simulator
    super.init()
  }

  // MARK: - Private

  private class var predicateForVideoPaths: NSPredicate {
    predicateForPaths(matchingTypes: [.movie, .mpeg4Movie, .quickTimeMovie])
  }

  private class var predicateForPhotoPaths: NSPredicate {
    var types: [UTType] = [.heic, .image, .jpeg, .png]
    if let jpeg2000 = UTType("public.jpeg-2000") {
      types.append(jpeg2000)
    }
    return predicateForPaths(matchingTypes: types)
  }

  private class var predicateForContactPaths: NSPredicate {
    predicateForPaths(matchingTypes: [.vCard])
  }

  private class var predicateForMediaPaths: NSPredicate {
    NSCompoundPredicate(orPredicateWithSubpredicates: [
      predicateForVideoPaths,
      predicateForPhotoPaths,
      predicateForContactPaths,
    ])
  }

  fileprivate func uploadMedia(_ mediaFileURLs: [URL]) throws {
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
      let stateString = (simulator.device.stateString() as String?) ?? "unknown"
      throw FBSimulatorError.describe("Simulator must be booted to upload photos, is \(stateString)").build()
    }

    let photosAndVideos =
      (mediaFileURLs as NSArray).filtered(
        using: NSCompoundPredicate(orPredicateWithSubpredicates: [
          FBSimulatorMediaCommands.predicateForPhotoPaths,
          FBSimulatorMediaCommands.predicateForVideoPaths,
        ])
      ) as! [URL]
    if !photosAndVideos.isEmpty {
      do {
        try simulator.device.addMedia(photosAndVideos)
      } catch {
        throw FBSimulatorError.describe("Failed to add media \(photosAndVideos)").caused(by: error as NSError).build()
      }
    }

    let contacts = (mediaFileURLs as NSArray).filtered(using: FBSimulatorMediaCommands.predicateForContactPaths) as! [URL]
    if !contacts.isEmpty {
      do {
        try simulator.device.addMedia(contacts)
      } catch {
        throw FBSimulatorError.describe("Failed to add contacts \(contacts)").caused(by: error as NSError).build()
      }
    }
  }

  private class func predicateForPaths(matchingTypes types: [UTType]) -> NSPredicate {
    NSPredicate { (evaluatedObject: Any?, _: [String: Any]?) -> Bool in
      guard let url = evaluatedObject as? URL else { return false }
      guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
      return types.contains { contentType.conforms(to: $0) }
    }
  }
}

// MARK: - FBSimulator+AsyncMediaCommands

extension FBSimulator: AsyncMediaCommands {

  public func addMedia(_ mediaFileURLs: [URL]) async throws {
    try mediaCommands().uploadMedia(mediaFileURLs)
  }
}
