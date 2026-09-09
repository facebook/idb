/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

public enum FBOToolError: Error {
  case bundleInaccessible(path: String)
  case bundleMissingExecutable(path: String)
}

extension FBOToolError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .bundleInaccessible(path):
      return "Bundle '\(path)' does not identify an accessible bundle directory."
    case let .bundleMissingExecutable(path):
      return "The bundle at \(path) does not contain an executable."
    }
  }
}

public final class FBOToolOperation {

  public static func listSanitiserDylibsRequired(byBundle testBundlePath: String) async throws -> [String] {
    guard let bundle = Bundle(path: testBundlePath) else {
      throw FBOToolError.bundleInaccessible(path: testBundlePath)
    }
    guard let executablePath = bundle.executablePath else {
      throw FBOToolError.bundleMissingExecutable(path: testBundlePath)
    }

    let result = try await Subprocess(executable: "/usr/bin/otool", arguments: ["-L", executablePath])
      .run()
    return extractSanitiserDylibs(fromOtoolOutput: result.standardOutput)
  }

  private static func extractSanitiserDylibs(fromOtoolOutput otoolOutput: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: "@rpath/(libclang_rt\\..*san_.*_dynamic.dylib)", options: .caseInsensitive) else {
      return []
    }
    var libs: [String] = []
    let nsString = otoolOutput as NSString
    regex.enumerateMatches(in: otoolOutput, options: [], range: NSRange(location: 0, length: nsString.length)) { result, _, _ in
      guard let result else { return }
      let range = result.range(at: 1)
      libs.append(nsString.substring(with: range))
    }
    return libs
  }
}
