/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

struct SwiftModuleMap {
  struct Module: Codable {
    let moduleName: String
    let isFramework: Bool
    let modulePath: String?
    let clangModulePath: String?
    let clangModuleMapPath: String?
  }

  let entries: [Module]

  init(entries: [Module]) {
    self.entries = entries
  }

  init(path: String) throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    entries = try JSONDecoder().decode([Module].self, from: data)
  }
}
