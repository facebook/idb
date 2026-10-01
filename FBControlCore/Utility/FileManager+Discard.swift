/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension FileManager {

  /// Removes the item at `url` from its path at once, deleting its contents in
  /// the background: deleting an app bundle of tens of thousands of files takes
  /// seconds, and renaming it out of the way does not.
  public func discardItem(at url: URL) throws {
    guard let trash = try? self.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true) else {
      try removeItem(at: url)
      return
    }
    do {
      try moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
    } catch {
      try? removeItem(at: trash)
      try removeItem(at: url)
      return
    }
    DispatchQueue.global(qos: .utility).async {
      try? FileManager.default.removeItem(at: trash)
    }
  }
}
