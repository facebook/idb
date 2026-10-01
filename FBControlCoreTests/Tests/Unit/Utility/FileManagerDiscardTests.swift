/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite
struct FileManagerDiscardTests {

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let fileManager = FileManager.default

  @Test
  func discardItem_FreesThePathForAReplacement() throws {
    let bundle = root.appendingPathComponent("A.app")
    try fileManager.createDirectory(at: bundle.appendingPathComponent("Frameworks"), withIntermediateDirectories: true)
    try Data("old".utf8).write(to: bundle.appendingPathComponent("Frameworks/F"))

    try fileManager.discardItem(at: bundle)

    #expect(!fileManager.fileExists(atPath: bundle.path))
    try fileManager.createDirectory(at: bundle, withIntermediateDirectories: false)
    #expect(try fileManager.contentsOfDirectory(atPath: bundle.path).isEmpty)
  }

  @Test
  func discardItem_ThrowsForAMissingItem() throws {
    #expect(throws: CocoaError.self) {
      try fileManager.discardItem(at: root.appendingPathComponent("missing"))
    }
  }
}
