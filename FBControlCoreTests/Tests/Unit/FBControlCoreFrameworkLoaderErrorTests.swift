/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import Testing

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

}
