/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment#Determine-Whether-Your-App-Is-Running-as-a-Translated-Binary
private func processIsTranslated() -> Int32 {
  var ret: Int32 = 0
  var size = MemoryLayout<Int32>.size
  // patternlint-disable-next-line prefer-metasystemcontrol-byname
  let result = sysctlbyname("sysctl.proc_translated", &ret, &size, nil, 0)
  if result == -1 {
    if errno == ENOENT {
      return 0
    }
    return -1
  }
  return ret
}

@objc(FBArchitectureProcessAdapter)
public class FBArchitectureProcessAdapter: NSObject {

  /// Force binaries to be launched in desired architectures.
  ///
  /// Convenience method for `adaptProcessConfiguration(_:toAnyArchitectureIn:hostArchitectures:queue:temporaryDirectory:)`
  @objc public func adaptProcessConfiguration(
    _ processConfiguration: FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>,
    toAnyArchitectureIn requestedArchitectures: Set<FBArchitecture>,
    queue: DispatchQueue,
    temporaryDirectory: URL
  ) -> FBFuture<FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>> {
    return adaptProcessConfiguration(
      processConfiguration,
      toAnyArchitectureIn: requestedArchitectures,
      hostArchitectures: FBArchitectureProcessAdapter.hostMachineSupportedArchitectures(),
      queue: queue,
      temporaryDirectory: temporaryDirectory
    )
  }

  private func selectArchitecture(
    from requestedArchitectures: Set<FBArchitecture>,
    supportedArchitectures: Set<FBArchitecture>
  ) -> FBArchitecture? {
    if requestedArchitectures.contains(.arm64) && supportedArchitectures.contains(.arm64) {
      return .arm64
    }
    if requestedArchitectures.contains(.X86_64) && supportedArchitectures.contains(.X86_64) {
      return .X86_64
    }
    return nil
  }

  /// Force binaries to be launched in desired architectures.
  @objc public func adaptProcessConfiguration(
    _ processConfiguration: FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>,
    toAnyArchitectureIn requestedArchitectures: Set<FBArchitecture>,
    hostArchitectures: Set<FBArchitecture>,
    queue: DispatchQueue,
    temporaryDirectory: URL
  ) -> FBFuture<FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>> {
    guard let architecture = selectArchitecture(from: requestedArchitectures, supportedArchitectures: hostArchitectures) else {
      return FBControlCoreError
        .describe("Could not select an architecture from \(FBCollectionInformation.oneLineDescription(from: Array(requestedArchitectures))) compatible with \(FBCollectionInformation.oneLineDescription(from: Array(hostArchitectures)))")
        .failFuture() as! FBFuture<FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>>
    }

    return unsafeBitCast(
      verifyArchitectureAvailable(processConfiguration.launchPath, architecture: architecture, queue: queue)
      .onQueue(queue, fmap: { (_: AnyObject) -> FBFuture<AnyObject> in
        let fileName = (processConfiguration.launchPath as NSString).lastPathComponent + UUID().uuidString + "." + (architecture.rawValue)
        let filePath = temporaryDirectory.appendingPathComponent(fileName, isDirectory: false)
        return self.extractArchitecture(architecture, processConfiguration: processConfiguration, queue: queue, outputPath: filePath)
            .mapReplace(filePath.path as NSString)
      })
      .onQueue(queue, fmap: { (extractedBinaryObj: AnyObject) -> FBFuture<AnyObject> in
        let extractedBinary = extractedBinaryObj as! String
        return self.getFixedupDyldFrameworkPath(fromOriginalBinary: processConfiguration.launchPath, queue: queue)
          .onQueue(queue, map: { (dyldFrameworkPathObj: AnyObject) -> AnyObject in
            let dyldFrameworkPath = dyldFrameworkPathObj as! String
            var updatedEnvironment = processConfiguration.environment as [String: String]
            // DYLD_FRAMEWORK_PATH adds additional search paths for required "*.framework"s in binary
            // DYLD_LIBRARY_PATH adds additional search paths for required "*.dylib"s in binary
            updatedEnvironment["DYLD_FRAMEWORK_PATH"] = dyldFrameworkPath
            updatedEnvironment["DYLD_LIBRARY_PATH"] = dyldFrameworkPath
            return FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>(
              launchPath: extractedBinary,
              arguments: processConfiguration.arguments,
              environment: updatedEnvironment as [String: String],
              io: processConfiguration.io,
              mode: processConfiguration.mode
            )
          })
      }),
      to: FBFuture<FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>>.self
    )
  }

  /// Verifies that we can extract desired architecture from binary
  private func verifyArchitectureAvailable(
    _ binary: String,
    architecture: FBArchitecture,
    queue: DispatchQueue
  ) -> FBFuture<NSNull> {
    let timeoutDescription = "lipo -verify_arch"
    return unsafeBitCast(
      FBProcessBuilder<AnyObject, NSNull, NSNull>
        .withLaunchPath("/usr/bin/lipo", arguments: [binary, "-verify_arch", architecture.rawValue])
        .withStdOutToDevNull()
        .withStdErrToDevNull()
        .runUntilCompletion(withAcceptableExitCodes: [0])
        .rephraseFailure("Desired architecture \(architecture) not found in \(binary) binary")
        .mapReplace(NSNull())
        .onQueue(queue, timeout: 20, handler: {
          return FBControlCoreError
            .describe("Timed out after 20.0s waiting for \(timeoutDescription)")
            .failFuture()
        }),
      to: FBFuture<NSNull>.self
    )
  }

  private func extractArchitecture(
    _ architecture: FBArchitecture,
    processConfiguration: FBProcessSpawnConfiguration<AnyObject, AnyObject, AnyObject>,
    queue: DispatchQueue,
    outputPath: URL
  ) -> FBFuture<NSNull> {
    let timeoutDescription = "lipo -extract"
    return unsafeBitCast(
      FBProcessBuilder<AnyObject, NSNull, AnyObject>
        .withLaunchPath("/usr/bin/lipo", arguments: [processConfiguration.launchPath, "-extract", architecture.rawValue, "-output", outputPath.path])
        .withStdOutToDevNull()
        .withStdErrLineReader({ (line: String) in
          NSLog("LINE %@\n", line)
        })
        .runUntilCompletion(withAcceptableExitCodes: [0])
        .rephraseFailure("Failed to thin \(architecture) architecture out from \(processConfiguration.launchPath) binary")
        .mapReplace(NSNull())
        .onQueue(queue, timeout: 10, handler: {
          return FBControlCoreError
            .describe("Timed out after 10.0s waiting for \(timeoutDescription)")
            .failFuture()
        }),
      to: FBFuture<NSNull>.self
    )
  }

  /// After we lipoed out arch from binary, new binary placed into temporary folder.
  /// That makes all dynamic library imports become incorrect. To fix that up we
  /// have to specify `DYLD_FRAMEWORK_PATH` correctly.
  private func getFixedupDyldFrameworkPath(
    fromOriginalBinary binary: String,
    queue: DispatchQueue
  ) -> FBFuture<NSString> {
    let binaryFolder = ((binary as NSString).resolvingSymlinksInPath as NSString).deletingLastPathComponent

    return unsafeBitCast(
      unsafeBitCast(
        getOtoolInfo(fromBinary: binary, queue: queue),
        to: FBFuture<AnyObject>.self
      )
      .onQueue(queue, map: { (resultObj: AnyObject) -> AnyObject in
        let result = resultObj as! String
        return self.extractRpaths(fromOtoolOutput: result) as NSSet
      })
      .onQueue(queue, map: { (resultObj: AnyObject) -> AnyObject in
        let result = resultObj as! Set<String>
        var rpaths: [String] = []
        for binaryRpath in result {
          if binaryRpath.hasPrefix("@executable_path") {
            rpaths.append(binaryRpath.replacingOccurrences(of: "@executable_path", with: binaryFolder))
          }
        }
        return rpaths.joined(separator: ":") as NSString
      }),
      to: FBFuture<NSString>.self
    )
  }

  private func getOtoolInfo(
    fromBinary binary: String,
    queue: DispatchQueue
  ) -> FBFuture<NSString> {
    let timeoutDescription = "otool -l"
    return unsafeBitCast(
      FBProcessBuilder<AnyObject, NSString, NSNull>
        .withLaunchPath("/usr/bin/otool", arguments: ["-l", binary])
        .withStdOutInMemoryAsString()
        .withStdErrToDevNull()
        .runUntilCompletion(withAcceptableExitCodes: [0])
        .rephraseFailure("Failed query otool -l from \(binary)")
        .onQueue(queue, fmap: { task -> FBFuture<AnyObject> in
          let subprocess = task as! FBSubprocess<AnyObject, NSString, NSNull>
          if let stdOut = subprocess.stdOut {
            return FBFuture<AnyObject>(result: stdOut)
          }
          return FBControlCoreError
            .describe("Failed to call otool -l over \(binary)")
            .failFuture()
        })
      .onQueue(queue, timeout: 10, handler: {
        return FBControlCoreError
          .describe("Timed out after 10.0s waiting for \(timeoutDescription)")
          .failFuture()
      }),
      to: FBFuture<NSString>.self
    )
  }

  /// Extracts rpath from full otool output.
  /// Each `LC_RPATH` entry like
  /// ```
  /// Load command 19
  ///   cmd LC_RPATH
  ///   cmdsize 48
  ///    path @executable_path/../../Frameworks/ (offset 12)
  /// ```
  /// transforms to
  /// ```
  /// @executable_path/../../Frameworks/
  /// ```
  private func extractRpaths(fromOtoolOutput otoolOutput: String) -> Set<String> {
    let lines = otoolOutput.components(separatedBy: "\n")
    var result = Set<String>()

    // Rpath entry looks like:
    // ```
    // Load command 19
    //   cmd LC_RPATH
    //   cmdsize 48
    //    path @executable_path/../../Frameworks/ (offset 12)
    // ```
    // So if we found occurence of `cmd LC_RPATH` rpath value will be two lines below.
    let lcRpathValueOffset = 2

    for (index, line) in lines.enumerated() {
      if isLcPathDefinitionLine(line) && index + lcRpathValueOffset < lines.count {
        let rpathLine = lines[index + lcRpathValueOffset]
        if let rpath = extractRpathValue(fromLine: rpathLine) {
          result.insert(rpath)
        }
      }
    }
    return result
  }

  /// Checking for `LC_RPATH` in load commands
  private func isLcPathDefinitionLine(_ line: String) -> Bool {
    var hasCMD = false
    var hasLcRpath = false
    for component in line.components(separatedBy: " ") {
      if component == "cmd" {
        hasCMD = true
      } else if component == "LC_RPATH" {
        hasLcRpath = true
      }
    }
    return hasCMD && hasLcRpath
  }

  // Note: spaces in path names are not available. Currently we use adapter for binaries
  // inside Xcode that has relative paths to original binary.
  // And there is no spaces in paths over there.
  private func extractRpathValue(fromLine line: String) -> String? {
    for component in line.components(separatedBy: " ") {
      if component.hasPrefix("@executable_path") {
        return component
      }
    }
    return nil
  }

  /// Returns supported architectures based on companion launch architecture and launch under rosetta determination.
  @objc public class func hostMachineSupportedArchitectures() -> Set<FBArchitecture> {
    #if arch(x86_64)
    let isTranslated = processIsTranslated()
    if isTranslated == 1 {
      // Companion running as x86_64 with translation (Rosetta) -> Processor supports Arm64 and x86_64
      return [.arm64, .X86_64]
    } else {
      // Companion running as x86_64 and translation is disabled or unknown
      // Assuming processor only supports x86_64 even if translation state is unknown
      return [.X86_64]
    }
    #else
    return [.arm64, .X86_64]
    #endif
  }
}
