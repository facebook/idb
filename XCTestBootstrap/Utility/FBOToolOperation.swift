/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

@objc public final class FBOToolOperation: NSObject {

  @objc public static func listSanitiserDylibsRequired(byBundle testBundlePath: String, onQueue queue: DispatchQueue) -> FBFuture<NSArray> {
    guard let bundle = Bundle(path: testBundlePath) else {
      let message = "Bundle '\(testBundlePath)' does not identify an accessible bundle directory."
      return FBFuture(error: XCTestBootstrapError.describe(message).build())
    }
    guard let executablePath = bundle.executablePath else {
      let message = "The bundle at \(testBundlePath) does not contain an executable."
      return FBFuture(error: XCTestBootstrapError.describe(message).build())
    }

    let base = FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/usr/bin/otool", arguments: ["-L", executablePath])
    let withStdOut = base.withStdOutInMemoryAsString()
    let configured = withStdOut.withStdErrInMemoryAsString()
    return unsafeBitCast(
      unsafeBitCast(
        configured.runUntilCompletion(withAcceptableExitCodes: [0]),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(
        queue,
        map: { task -> AnyObject in
          let subprocess = task as! FBSubprocess<AnyObject, NSString, NSString>
          return FBOToolOperation.extractSanitiserDylibs(fromOtoolOutput: subprocess.stdOut! as String) as NSArray
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
      if let result {
        let range = result.range(at: 1)
        libs.append(nsString.substring(with: range))
      }
    }
    return libs
  }
}
