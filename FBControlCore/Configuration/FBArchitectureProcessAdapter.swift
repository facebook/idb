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

enum ArchitectureAdapterError: Error, LocalizedError {
  case noCompatibleArchitecture(requested: [String], host: [String])
  case timedOut(seconds: Double, waitingFor: String)
  case verificationFailed(architecture: String, binary: String)
  case extractionFailed(architecture: String, binary: String)
  case otoolFailed(binary: String)

  public var errorDescription: String? {
    switch self {
    case let .noCompatibleArchitecture(requested, host):
      return "Could not select an architecture from \(FBCollectionInformation.oneLineDescription(from: requested)) compatible with \(FBCollectionInformation.oneLineDescription(from: host))"
    case let .timedOut(seconds, waitingFor):
      return "Timed out after \(String(format: "%.1f", seconds))s waiting for \(waitingFor)"
    case let .verificationFailed(architecture, binary):
      return "Desired architecture \(architecture) not found in \(binary) binary"
    case let .extractionFailed(architecture, binary):
      return "Failed to thin \(architecture) architecture out from \(binary) binary"
    case let .otoolFailed(binary):
      return "Failed query otool -l from \(binary)"
    }
  }
}

public enum FBArchitectureProcessAdapter {

  private static func selectArchitecture(
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
  public static func adaptProcessConfiguration(
    _ processConfiguration: FBProcessSpawnConfiguration,
    toAnyArchitectureIn requestedArchitectures: Set<FBArchitecture>,
    hostArchitectures: Set<FBArchitecture> = FBArchitectureProcessAdapter.hostMachineSupportedArchitectures(),
    temporaryDirectory: URL
  ) async throws -> FBProcessSpawnConfiguration {
    guard let architecture = selectArchitecture(from: requestedArchitectures, supportedArchitectures: hostArchitectures) else {
      throw ArchitectureAdapterError.noCompatibleArchitecture(requested: requestedArchitectures.map(\.rawValue), host: hostArchitectures.map(\.rawValue))
    }

    try await verifyArchitectureAvailable(processConfiguration.launchPath, architecture: architecture)

    let fileName = (processConfiguration.launchPath as NSString).lastPathComponent + UUID().uuidString + "." + (architecture.rawValue)
    let filePath = temporaryDirectory.appendingPathComponent(fileName, isDirectory: false)
    try await extractArchitecture(architecture, launchPath: processConfiguration.launchPath, outputPath: filePath)

    let dyldFrameworkPath = try await getFixedupDyldFrameworkPath(fromOriginalBinary: processConfiguration.launchPath)
    var updatedEnvironment = processConfiguration.environment as [String: String]
    updatedEnvironment["DYLD_FRAMEWORK_PATH"] = dyldFrameworkPath
    updatedEnvironment["DYLD_LIBRARY_PATH"] = dyldFrameworkPath
    return FBProcessSpawnConfiguration(
      launchPath: filePath.path,
      arguments: processConfiguration.arguments,
      environment: updatedEnvironment,
      io: processConfiguration.io,
      mode: processConfiguration.mode
    )
  }

  /// Verifies that we can extract desired architecture from binary
  private static func verifyArchitectureAvailable(
    _ binary: String,
    architecture: FBArchitecture
  ) async throws {
    let result = try await withTimeout(seconds: 20, waitingFor: "lipo -verify_arch") {
      try await Subprocess(executable: "/usr/bin/lipo", arguments: [binary, "-verify_arch", architecture.rawValue])
        .run(output: .closed, error: .closed, exitPolicy: .any)
    }
    try result.checkExitedCleanly(
      orThrow: ArchitectureAdapterError.verificationFailed(architecture: architecture.rawValue, binary: binary))
  }

  private static func extractArchitecture(
    _ architecture: FBArchitecture,
    launchPath: String,
    outputPath: URL
  ) async throws {
    let result = try await withTimeout(seconds: 10, waitingFor: "lipo -extract") {
      try await Subprocess(executable: "/usr/bin/lipo", arguments: [launchPath, "-extract", architecture.rawValue, "-output", outputPath.path])
        .run(
          output: .closed,
          error: .lines { line in
            NSLog("LINE %@\n", line)
          },
          exitPolicy: .any)
    }
    try result.checkExitedCleanly(
      orThrow: ArchitectureAdapterError.extractionFailed(architecture: architecture.rawValue, binary: launchPath))
  }

  /// After we lipoed out arch from binary, new binary placed into temporary folder.
  /// That makes all dynamic library imports become incorrect. To fix that up we
  /// have to specify `DYLD_FRAMEWORK_PATH` correctly.
  private static func getFixedupDyldFrameworkPath(
    fromOriginalBinary binary: String
  ) async throws -> String {
    let binaryFolder = ((binary as NSString).resolvingSymlinksInPath as NSString).deletingLastPathComponent

    let otoolOutput = try await getOtoolInfo(fromBinary: binary)
    var rpaths: [String] = []
    for binaryRpath in extractRpaths(fromOtoolOutput: otoolOutput) {
      if binaryRpath.hasPrefix("@executable_path") {
        rpaths.append(binaryRpath.replacingOccurrences(of: "@executable_path", with: binaryFolder))
      }
    }
    return rpaths.joined(separator: ":")
  }

  private static func getOtoolInfo(
    fromBinary binary: String
  ) async throws -> String {
    let result = try await withTimeout(seconds: 10, waitingFor: "otool -l") {
      try await Subprocess(executable: "/usr/bin/otool", arguments: ["-l", binary])
        .run(output: .string, error: .closed, exitPolicy: .any)
    }
    try result.checkExitedCleanly(orThrow: ArchitectureAdapterError.otoolFailed(binary: binary))
    return result.standardOutput
  }

  /// Races `operation` against a deadline. On timeout the error is thrown to the
  /// caller and the losing task is cancelled — which stops observation of a
  /// spawned process without killing it, matching the future-timeout behaviour
  /// this replaces.
  private static func withTimeout<Result: Sendable>(
    seconds: Double,
    waitingFor description: String,
    _ operation: @escaping @Sendable () async throws -> Result
  ) async throws -> Result {
    try await withThrowingTaskGroup(of: Result.self) { group in
      group.addTask {
        try await operation()
      }
      group.addTask {
        try await Task.sleep(for: .seconds(seconds))
        throw ArchitectureAdapterError.timedOut(seconds: seconds, waitingFor: description)
      }
      guard let result = try await group.next() else {
        preconditionFailure("The task group has two children; next() cannot be empty")
      }
      group.cancelAll()
      return result
    }
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
  private static func extractRpaths(fromOtoolOutput otoolOutput: String) -> Set<String> {
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
  private static func isLcPathDefinitionLine(_ line: String) -> Bool {
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
  private static func extractRpathValue(fromLine line: String) -> String? {
    for component in line.components(separatedBy: " ") {
      if component.hasPrefix("@executable_path") {
        return component
      }
    }
    return nil
  }

  /// Returns supported architectures based on companion launch architecture and launch under rosetta determination.
  public static func hostMachineSupportedArchitectures() -> Set<FBArchitecture> {
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
