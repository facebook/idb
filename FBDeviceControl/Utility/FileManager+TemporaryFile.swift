/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension FileManager {
  func temporaryFile(extension fileExtension: String) throws -> URL {
    let tmpPath = try url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: URL(fileURLWithPath: "/tmp"), create: true)
    if #available(macOS 13.0, *) {
      return tmpPath.appending(component: "\(ProcessInfo().globallyUniqueString).\(fileExtension)")
    } else {
      return tmpPath.appendingPathComponent("\(ProcessInfo().globallyUniqueString)", isDirectory: false)
    }
  }
}
