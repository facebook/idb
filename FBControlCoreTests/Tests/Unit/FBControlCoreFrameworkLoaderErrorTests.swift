/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import Testing

/// Counts `loadPrivateFrameworks` calls without dlopening anything, in the style of the double in
/// `FBSimulatorIndigoHIDTests`.
private final class RecordingFrameworkLoader: FBControlCoreFrameworkLoader {

  private(set) var loadCount = 0

  override func loadPrivateFrameworks(_ logger: FBControlCoreLogger?) throws {
    loadCount += 1
  }
}

/// The two sides of the loader's error contract: the throwing entry point produces a descriptive
/// error, while `loadPrivateFrameworksOrAbort()` can only be observed on its success path — its
/// failure branch logs, asserts, and `abort()`s, which kills the test runner and so cannot be
/// pinned in-process.
@Suite("Framework loader error contract")
struct FBControlCoreFrameworkLoaderErrorTests {

  @Test("A throwing load surfaces a descriptive error for an unloadable framework")
  func throwingLoadSurfacesADescriptiveError() throws {
    let missingPath = "/var/empty/Nonexistent.framework"
    let framework = FBWeakFramework.framework(
      withPath: missingPath,
      requiredClassNames: ["IDBNonexistentClass"],
      rootPermitted: false
    )
    let loader = FBControlCoreFrameworkLoader(name: "TestFrameworks", frameworks: [framework])

    let error = #expect(throws: (any Error).self) {
      try loader.loadPrivateFrameworks(nil)
    }

    let description = try #require(error).localizedDescription
    #expect(description.contains(missingPath))
  }

  @Test("loadPrivateFrameworksOrAbort returns normally when loading succeeds")
  func orAbortReturnsNormallyWhenLoadingSucceeds() {
    let loader = RecordingFrameworkLoader(name: "TestFrameworks", frameworks: [])

    loader.loadPrivateFrameworksOrAbort()

    #expect(loader.loadCount == 1)
  }
}
