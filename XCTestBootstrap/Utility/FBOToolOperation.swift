/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// The ways otool inspection can fail, as data rather than assembled strings.
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

  public static func listSanitiserDylibsRequired(byBundle testBundlePath: String, onQueue queue: DispatchQueue) -> FBFuture<NSArray> {
    guard let bundle = Bundle(path: testBundlePath) else {
      return FBFuture(error: FBOToolError.bundleInaccessible(path: testBundlePath))
    }
    guard let executablePath = bundle.executablePath else {
      return FBFuture(error: FBOToolError.bundleMissingExecutable(path: testBundlePath))
    }

    let base = FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/usr/bin/otool", arguments: ["-L", executablePath])
    let withStdOut = base.withStdOutInMemoryAsString()
    let configured = withStdOut.withStdErrInMemoryAsString()
    return unsafeBitCast(
      configured.runUntilCompletion(withAcceptableExitCodes: [0])
        .onQueue(
          queue,
          map: { subprocess -> AnyObject in
            FBOToolOperation.extractSanitiserDylibs(fromOtoolOutput: (subprocess.stdOut as String?) ?? "") as NSArray
          }),
      to: FBFuture<NSArray>.self
    )
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
