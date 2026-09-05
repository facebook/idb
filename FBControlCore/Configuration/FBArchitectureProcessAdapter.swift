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

public enum FBArchitectureAdapterError: Error, LocalizedError {
  case noCompatibleArchitecture(requested: [String], host: [String])
  case timedOut(seconds: Double, waitingFor: String)
  case otoolFailed(binary: String)

  public var errorDescription: String? {
    switch self {
    case let .noCompatibleArchitecture(requested, host):
      return "Could not select an architecture from \(FBCollectionInformation.oneLineDescription(from: requested)) compatible with \(FBCollectionInformation.oneLineDescription(from: host))"
    case let .timedOut(seconds, waitingFor):
      return "Timed out after \(String(format: "%.1f", seconds))s waiting for \(waitingFor)"
    case let .otoolFailed(binary):
      return "Failed to call otool -l over \(binary)"
    }
  }
}

@objc(FBArchitectureProcessAdapter)
public final class FBArchitectureProcessAdapter: NSObject {

  /// As the `hostArchitectures:` overload, using the host machine's supported architectures.
  @objc public func adaptProcessConfiguration(
    _ processConfiguration: FBProcessSpawnConfiguration,
    toAnyArchitectureIn requestedArchitectures: Set<FBArchitecture>,
    queue: DispatchQueue,
    temporaryDirectory: URL
  ) -> FBFuture<FBProcessSpawnConfiguration> {
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
    _ processConfiguration: FBProcessSpawnConfiguration,
    toAnyArchitectureIn requestedArchitectures: Set<FBArchitecture>,
    hostArchitectures: Set<FBArchitecture>,
    queue: DispatchQueue,
    temporaryDirectory: URL
  ) -> FBFuture<FBProcessSpawnConfiguration> {
    guard let architecture = selectArchitecture(from: requestedArchitectures, supportedArchitectures: hostArchitectures) else {
      return FBFuture(error: FBArchitectureAdapterError.noCompatibleArchitecture(requested: requestedArchitectures.map(\.rawValue), host: hostArchitectures.map(\.rawValue)))
    }

    return unsafeBitCast(
      verifyArchitectureAvailable(processConfiguration.launchPath, architecture: architecture, queue: queue)
        .onQueue(
          queue,
          fmap: { (_: AnyObject) -> FBFuture<AnyObject> in
            let fileName = (processConfiguration.launchPath as NSString).lastPathComponent + UUID().uuidString + "." + (architecture.rawValue)
            let filePath = temporaryDirectory.appendingPathComponent(fileName, isDirectory: false)
            return self.extractArchitecture(architecture, processConfiguration: processConfiguration, queue: queue, outputPath: filePath)
              .mapReplace(filePath.path as NSString)
          }
        )
        .retyped(FBFuture<NSString>.self)
        .onQueue(
          queue,
          fmap: { extractedBinary -> FBFuture<AnyObject> in
            return self.getFixedupDyldFrameworkPath(fromOriginalBinary: processConfiguration.launchPath, queue: queue)
              .onQueue(
                queue,
                map: { dyldFrameworkPath -> AnyObject in
                  var updatedEnvironment = processConfiguration.environment as [String: String]
                  updatedEnvironment["DYLD_FRAMEWORK_PATH"] = dyldFrameworkPath as String
                  updatedEnvironment["DYLD_LIBRARY_PATH"] = dyldFrameworkPath as String
                  return FBProcessSpawnConfiguration(
                    launchPath: extractedBinary as String,
                    arguments: processConfiguration.arguments,
                    environment: updatedEnvironment as [String: String],
                    io: processConfiguration.io,
                    mode: processConfiguration.mode
                  )
                })
          }),
      to: FBFuture<FBProcessSpawnConfiguration>.self
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
        .onQueue(
          queue, timeout: 20,
          handler: {
            FBFuture<AnyObject>(error: FBArchitectureAdapterError.timedOut(seconds: 20.0, waitingFor: timeoutDescription))
          }),
      to: FBFuture<NSNull>.self
    )
  }

  private func extractArchitecture(
    _ architecture: FBArchitecture,
    processConfiguration: FBProcessSpawnConfiguration,
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
        .onQueue(
          queue, timeout: 10,
          handler: {
            FBFuture<AnyObject>(error: FBArchitectureAdapterError.timedOut(seconds: 10.0, waitingFor: timeoutDescription))
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

    return getOtoolInfo(fromBinary: binary, queue: queue)
      .onQueue(
        queue,
        map: { otoolOutput -> AnyObject in
          var rpaths: [String] = []
          for binaryRpath in self.extractRpaths(fromOtoolOutput: otoolOutput as String) {
            if binaryRpath.hasPrefix("@executable_path") {
              rpaths.append(binaryRpath.replacingOccurrences(of: "@executable_path", with: binaryFolder))
            }
          }
          return rpaths.joined(separator: ":") as NSString
        }
      )
      .retyped(FBFuture<NSString>.self)
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
        .onQueue(
          queue,
          fmap: { subprocess -> FBFuture<AnyObject> in
            if let stdOut = subprocess.stdOut {
              return FBFuture<AnyObject>(result: stdOut)
            }
            return FBFuture(error: FBArchitectureAdapterError.otoolFailed(binary: binary))
          }
        )
        .onQueue(
          queue, timeout: 10,
          handler: {
            FBFuture<AnyObject>(error: FBArchitectureAdapterError.timedOut(seconds: 10.0, waitingFor: timeoutDescription))
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

  // Splits on spaces, so rpaths containing spaces are unsupported; the Xcode binaries this adapts have none.
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
