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

/// The ways media upload can fail, as data rather than assembled strings.
public enum FBSimulatorMediaError: Error {
  case noMediaProvided
  case unknownMediaPaths(paths: [URL])
  case simulatorNotBooted(state: String)
  case addMediaFailed(paths: [URL], underlying: Error)
  case addContactsFailed(paths: [URL], underlying: Error)
}

extension FBSimulatorMediaError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .noMediaProvided:
      return "Cannot upload media, none was provided"
    case let .unknownMediaPaths(paths):
      return "\(paths) not a known media path"
    case let .simulatorNotBooted(state):
      return "Simulator must be booted to upload photos, is \(state)"
    case let .addMediaFailed(paths, _):
      return "Failed to add media \(paths)"
    case let .addContactsFailed(paths, _):
      return "Failed to add contacts \(paths)"
    }
  }
}

public final class FBSimulatorMediaCommands: NSObject {

  // MARK: - Properties

  private weak var simulator: FBSimulator?

  // MARK: - Initializers

  public class func commands(with simulator: FBSimulator) -> FBSimulatorMediaCommands {
    FBSimulatorMediaCommands(simulator: simulator)
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
      throw FBWeakTargetError.simulator
    }

    if mediaFileURLs.isEmpty {
      throw FBSimulatorMediaError.noMediaProvided
    }

    let mediaPredicate = FBSimulatorMediaCommands.predicateForMediaPaths
    let unknown = mediaFileURLs.filter { !mediaPredicate.evaluate(with: $0) }
    if !unknown.isEmpty {
      throw FBSimulatorMediaError.unknownMediaPaths(paths: unknown)
    }

    if simulator.state != .booted {
      let stateString = (simulator.device.stateString() as String?) ?? "unknown"
      throw FBSimulatorMediaError.simulatorNotBooted(state: stateString)
    }

    let photosAndVideosPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
      FBSimulatorMediaCommands.predicateForPhotoPaths,
      FBSimulatorMediaCommands.predicateForVideoPaths,
    ])
    let photosAndVideos = mediaFileURLs.filter { photosAndVideosPredicate.evaluate(with: $0) }
    if !photosAndVideos.isEmpty {
      do {
        try FBObjCExceptionGuard.guarded {
          try simulator.device.addMedia(photosAndVideos)
        }
      } catch {
        throw FBSimulatorMediaError.addMediaFailed(paths: photosAndVideos, underlying: error)
      }
    }

    let contactPredicate = FBSimulatorMediaCommands.predicateForContactPaths
    let contacts = mediaFileURLs.filter { contactPredicate.evaluate(with: $0) }
    if !contacts.isEmpty {
      do {
        try FBObjCExceptionGuard.guarded {
          try simulator.device.addMedia(contacts)
        }
      } catch {
        throw FBSimulatorMediaError.addContactsFailed(paths: contacts, underlying: error)
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

// MARK: - FBSimulator+MediaCommands

extension FBSimulator: MediaCommands {

  public func addMedia(_ mediaFileURLs: [URL]) async throws {
    try mediaCommands().uploadMedia(mediaFileURLs)
  }
}
