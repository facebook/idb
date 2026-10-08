/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import Testing

/// The simulator is never booted, so an upload whose files are all recognised gets as far as the
/// boot check and no further.
@Suite
struct SimulatorMediaCommandsTests {

  private let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  private func file(_ name: String) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try Data().write(to: url)
    return url
  }

  private func upload(_ urls: [URL]) throws {
    try SimulatorMediaCommands.commands(with: SimulatorTestSupport.testableSimulator(withDevice: SimDeviceDouble())).upload(urls)
  }

  @Test
  func anUploadOfNothingIsRejected() {
    #expect {
      try upload([])
    } throws: { error in
      guard case SimulatorMediaError.noMediaProvided = error else { return false }
      return true
    }
  }

  @Test
  func photosVideosAndContactsAreAllRecognised() throws {
    let urls = try ["photo.png", "photo.jpg", "photo.heic", "movie.mp4", "movie.mov", "contact.vcf"].map(file)
    #expect {
      try upload(urls)
    } throws: { error in
      guard case SimulatorStateError.notBooted = error else { return false }
      return true
    }
  }

  @Test
  func onlyTheUnrecognisedFilesAreReported() throws {
    let photo = try file("photo.png")
    let notes = try file("notes.txt")
    #expect {
      try upload([photo, notes])
    } throws: { error in
      guard case SimulatorMediaError.unknownMediaPaths(let paths) = error else { return false }
      return paths == [notes]
    }
  }
}
