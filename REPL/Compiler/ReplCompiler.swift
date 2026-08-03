/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The parameters needed to compile a REPL submission into a dylib: the target
/// triple, the (optional) Apple SDK path, the Swift toolchain, the search paths /
/// auto-imported modules for the interfaces injected code may reference, and any
/// extra compiler or link arguments. These are resolved by the caller (see
/// `CompilerEnvironment`), so this type carries no assumptions.
public struct ReplCompileParameters {
  public var targetTriple: String
  public var sdkPath: String?
  public var toolchainPath: String
  /// Extra arguments added to the `swiftc` invocation for compiling.
  public var compilerArguments: [String]
  public var interfaceSearchPaths: [String]
  public var autoImportModules: [String]
  /// Extra arguments added to the `swiftc` invocation for linking.
  public var linkerArguments: [String]

  public init(
    targetTriple: String,
    sdkPath: String?,
    toolchainPath: String,
    compilerArguments: [String] = [],
    interfaceSearchPaths: [String] = [],
    autoImportModules: [String] = [],
    linkerArguments: [String] = []
  ) {
    self.targetTriple = targetTriple
    self.sdkPath = sdkPath
    self.toolchainPath = toolchainPath
    self.compilerArguments = compilerArguments
    self.interfaceSearchPaths = interfaceSearchPaths
    self.autoImportModules = autoImportModules
    self.linkerArguments = linkerArguments
  }
}

/// The outcome of one compile: either the dylib written to disk and the
/// entry-point symbol to call, or the (filtered) compiler output when the
/// compile failed.
public enum ReplCompileResult {
  case success(dylibPath: String, symbol: String)
  case failure(compilerOutput: String)
}

/// Compiles a block of user-entered REPL Swift into a loadable dylib. Shared
/// between `idb-repl` (the client) and `idb_companion` (the server) so injected
/// code can be compiled on either side of the connection. Free of process
/// globals -- all scratch I/O happens under the caller-provided
/// `workingDirectory` -- so it holds no shared state and can run in any host
/// tool.
public enum ReplCompiler {

  /// Generates the wrapped source for `userCode`, compiles it into a dylib under
  /// `workingDirectory`, and returns the dylib path plus its `idb_repl_<index>`
  /// entry-point symbol. Returns `.failure` (carrying the filtered compiler
  /// output) when swiftc exits non-zero; throws only on unexpected I/O failure.
  public static func compile(
    userCode: String,
    index: Int,
    parameters: ReplCompileParameters,
    workingDirectory: String
  ) throws -> ReplCompileResult {
    try FileManager.default.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)

    let symbol = "idb_repl_\(index)"
    let swiftPath = (workingDirectory as NSString).appendingPathComponent("run-\(index).swift")
    let dylibPath = (workingDirectory as NSString).appendingPathComponent("run-\(index).dylib")

    let source = ReplSourceGenerator.generateSource(
      for: userCode, index: index, autoImportModules: parameters.autoImportModules)
    try source.write(toFile: swiftPath, atomically: true, encoding: .utf8)

    let (status, compilerOutput) = try compileSwift(
      sourcePath: swiftPath,
      outputPath: dylibPath,
      index: index,
      parameters: parameters,
      workingDirectory: workingDirectory)
    try? FileManager.default.removeItem(atPath: swiftPath)

    guard status == 0 else {
      return .failure(compilerOutput: compilerOutput)
    }
    return .success(dylibPath: dylibPath, symbol: symbol)
  }

  // MARK: - Private

  private static func compileSwift(
    sourcePath: String,
    outputPath: String,
    index: Int,
    parameters: ReplCompileParameters,
    workingDirectory: String
  ) throws -> (Int32, String) {
    let swiftcPath = (parameters.toolchainPath as NSString).appendingPathComponent("usr/bin/swiftc")
    let swiftc = Process()
    swiftc.executableURL = URL(fileURLWithPath: swiftcPath)
    var environment = ProcessInfo.processInfo.environment
    if let sdkPath = parameters.sdkPath {
      environment["SDKROOT"] = sdkPath
    }
    swiftc.environment = environment
    var arguments = [
      sourcePath,
      "-emit-library", "-o", outputPath,
      "-target", parameters.targetTriple,
      // Give each submission a unique, predictable module name matching its
      // entry-point symbol.
      "-module-name", "idb_repl_\(index)",
    ]
    arguments.append(contentsOf: parameters.compilerArguments)
    // Add the probe-generated .swiftinterface directories to the import search
    // path so injected code can `import` the test bundle's modules. The symbols
    // themselves are resolved at load time via `-undefined dynamic_lookup`.
    for searchPath in parameters.interfaceSearchPaths {
      arguments.append(contentsOf: ["-I", searchPath])
    }
    arguments.append(contentsOf: ["-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup"])
    arguments.append(contentsOf: parameters.linkerArguments)
    swiftc.arguments = arguments
    // Redirect stdout/stderr to files rather than pipes: a file sink has no
    // fixed-size kernel buffer to fill, so a large compiler diagnostic can never
    // deadlock the child, and there is no need to drain two pipes concurrently.
    let stdoutPath = (workingDirectory as NSString).appendingPathComponent("run-\(index).stdout")
    let stderrPath = (workingDirectory as NSString).appendingPathComponent("run-\(index).stderr")
    FileManager.default.createFile(atPath: stdoutPath, contents: nil)
    FileManager.default.createFile(atPath: stderrPath, contents: nil)
    let stdoutHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: stdoutPath))
    let stderrHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: stderrPath))
    swiftc.standardOutput = stdoutHandle
    swiftc.standardError = stderrHandle
    try swiftc.run()
    swiftc.waitUntilExit()
    try? stdoutHandle.close()
    try? stderrHandle.close()

    let outputData = (try? Data(contentsOf: URL(fileURLWithPath: stdoutPath))) ?? Data()
    let errorData = (try? Data(contentsOf: URL(fileURLWithPath: stderrPath))) ?? Data()
    try? FileManager.default.removeItem(atPath: stdoutPath)
    try? FileManager.default.removeItem(atPath: stderrPath)

    let filters: [NSRegularExpression] = [
      try NSRegularExpression(pattern: #"ld: warning: -undefined dynamic_lookup is deprecated.*"#)
    ]

    var filteredLines: [String] = []

    for data in [outputData, errorData] {
      if let output = String(data: data, encoding: .utf8) {
        for line in output.components(separatedBy: "\n") {
          let range = NSRange(line.startIndex..., in: line)
          let filtered = filters.contains { $0.firstMatch(in: line, range: range) != nil }
          if !filtered && !line.isEmpty && !line.contains("// idb-repl-strip") {
            filteredLines.append(line.replacingOccurrences(of: workingDirectory, with: ""))
          }
        }
      }
    }

    return (swiftc.terminationStatus, filteredLines.joined(separator: "\n"))
  }
}
