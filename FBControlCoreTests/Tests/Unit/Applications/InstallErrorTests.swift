/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBArtifactStaging
@testable import FBControlCore
import Foundation
import Testing

@Suite
struct InstallErrorTests {

  @Test
  func extractionFailed_WhenTheArchiveIsCorrupt_DescribesTheReason() {
    let error = InstallError.extractionFailed(underlying: ArchiveError.corrupt("bad CRC for Payload/App.app/App"))

    #expect(error.description.contains("bad CRC for Payload/App.app/App"))
    #expect((error as NSError).localizedDescription.contains("bad CRC for Payload/App.app/App"))
  }
}
