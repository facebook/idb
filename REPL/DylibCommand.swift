/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// patternlint-disable cdecl-unsupported
// patternlint-disable avoid-print-to-prevent-production-overhead

import ArgumentParser
import Foundation

struct DylibCommand: ParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "dylib",
    abstract: "Run the test process for dylib injection")

  @OptionGroup var options: SharedOptions

  @Option(name: .long, help: "Path to the Swift module for the test target. Must end with a .swiftmodule file.")
  var swiftModule: String

  @Option(name: .long, help: "Path to the explicit Swift module map for the test target. Must end with a .json file.")
  var swiftModuleMap: String

  @Option(name: .long, help: "Path to the toolchain for the test target.")
  var toolchainPath: String

  @Option(name: .long, help: "Target platform (ios, macos).")
  var platform: Platform

  func validate() throws {
    guard (swiftModule as NSString).pathExtension == "swiftmodule" else {
      throw ValidationError("--swift-module path must end with a .swiftmodule file, got: \(swiftModule)")
    }
    guard (swiftModuleMap as NSString).pathExtension == "json" else {
      throw ValidationError("--swift-module-map path must end with a .json file, got: \(swiftModuleMap)")
    }
  }

  func run() throws {
    let (moduleMap, moduleMapPath) = try prepareModuleMap()
    let sdkPath = try resolveSDKPath(platform: platform)
    let targetTriple = try resolveTargetTriple(platform: platform)
    let (process, testPid) = try launchAndWaitForPid(options: options)
    var runIndex = 0

    printStatus("Found pid: \(testPid)")

    let socketPath = "/tmp/test_repl_\(testPid).sock"
    let socketFd = try connectToSocket(path: socketPath)
    defer {
      close(socketFd)
      unlink(socketPath)
    }

    printStatus("Connected to test process.", "Type '/help' for available commands.")

    var lines: [String] = []
    let editor = LineEditor()

    inputLoop: while let input = editor.readLine() {
      let trimmed = input.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }

      if trimmed.hasPrefix("/") {
        print("")
        switch trimmed {
        case "/run":
          let swiftCode = lines.joined(separator: "\n")
          handleRun(swiftCode: swiftCode, index: runIndex, moduleMap: moduleMap, moduleMapPath: moduleMapPath, targetTriple: targetTriple, sdkPath: sdkPath, socketFd: socketFd)
          runIndex += 1
          lines = []
        case "/help":
          printHelp()
        case "/exit":
          break inputLoop
        default:
          printStatus("Unknown command: '\(trimmed)'. Type '/help' for available commands.")
        }
      } else {
        lines.append(input)
      }
    }

    kill(process.processIdentifier, SIGKILL)
    process.waitUntilExit()
    sessionDirectory.cleanup()
  }

  private func prepareModuleMap() throws -> (moduleMap: SwiftModuleMap, path: String) {
    let original = try SwiftModuleMap(path: swiftModuleMap)
    let moduleName = ((swiftModule as NSString).lastPathComponent as NSString).deletingPathExtension
    let newModule = SwiftModuleMap.Module(
      moduleName: moduleName,
      isFramework: false,
      modulePath: swiftModule,
      clangModulePath: nil,
      clangModuleMapPath: nil
    )
    let updatedMap = SwiftModuleMap(entries: [newModule] + original.entries)
    let path = try sessionDirectory.filePath(named: "module-map.json")
    let data = try JSONEncoder().encode(updatedMap.entries)
    try data.write(to: URL(fileURLWithPath: path))
    return (updatedMap, path)
  }

  private func handleRun(swiftCode: String, index: Int, moduleMap: SwiftModuleMap, moduleMapPath: String, targetTriple: String, sdkPath: String, socketFd: Int32) {
    do {
      let swiftPath = try sessionDirectory.filePath(named: "run-\(index).swift")
      let dylibPath = try sessionDirectory.filePath(named: "run-\(index).dylib")

      let (userImports, strippedCode) = extractImports(from: swiftCode)
      _ = userImports
      let code = wrappedCode(swiftCode: strippedCode, index: index, moduleMap: moduleMap)
      try code.write(toFile: swiftPath, atomically: true, encoding: .utf8)

      let (status, compilerOutput) = try compileSwift(sourcePath: swiftPath, outputPath: dylibPath, moduleMapPath: moduleMapPath, targetTriple: targetTriple, sdkPath: sdkPath)

      if status == 0 {
        let response = try sendCommand(dylibPath: dylibPath, symbol: "test_\(index)", socketFd: socketFd)
        if response["success"] as? Bool == true {
          let result = response["result"] as? String ?? ""
          printStatus(result)
        } else {
          printStatus("Error:", "\(response["error"] ?? "unknown")")
        }
      } else {
        printStatus("Error:", compilerOutput)
      }

      try? FileManager.default.removeItem(atPath: swiftPath)
    } catch {
      printStatus("Error:", "\(error)")
    }
  }

  private func extractImports(from code: String) -> (imports: [String], strippedCode: String) {
    let pattern = #"(?:@\w+\s+)?import\s+([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)\s*;?"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return ([], code)
    }
    let nsCode = code as NSString
    let range = NSRange(location: 0, length: nsCode.length)
    let imports = regex.matches(in: code, range: range).map { match in
      nsCode.substring(with: match.range(at: 1))
    }
    let stripped = regex.stringByReplacingMatches(in: code, range: range, withTemplate: "")
    return (imports, stripped)
  }

  private func wrappedCode(swiftCode: String, index: Int, moduleMap: SwiftModuleMap) -> String {
    let imports = moduleMap.entries
      .filter { $0.modulePath != nil && !$0.moduleName.hasPrefix("_") }
      .map { module in
        let testable = module.modulePath?.contains("toolchain") == true ? "" : "@testable "
        return "\(testable)import \(module.moduleName) // test-repl-strip"
      }
      .joined(separator: "\n")
    let function =
      containsAsync(swiftCode)
      ? asyncFunction(swiftCode: swiftCode, index: index)
      : syncFunction(swiftCode: swiftCode, index: index)
    return """
      import Foundation // test-repl-strip
      \(imports)
      \(function)
      """
  }

  private func containsAsync(_ code: String) -> Bool {
    let pattern = #"\b(?:async|await)\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return false
    }
    let nsCode = code as NSString
    return regex.firstMatch(in: code, range: NSRange(location: 0, length: nsCode.length)) != nil
  }

  private func syncFunction(swiftCode: String, index: Int) -> String {
    return """
      private func userCode_\(index)() throws -> Any { // test-repl-strip
        \(swiftCode)
      } // test-repl-strip
      @_cdecl("test_\(index)") public func test_\(index)() -> UnsafePointer<CChar>? { // test-repl-strip
        let output: String // test-repl-strip
        do { // test-repl-strip
          let result = try userCode_\(index)() // test-repl-strip
          output = "Result:\\n\\(String(describing: result))" // test-repl-strip
        } catch { // test-repl-strip
          output = "Exception:\\n\\(String(describing: error))" // test-repl-strip
        } // test-repl-strip
        return output.withCString { UnsafePointer(strdup($0)) } // test-repl-strip
      } // test-repl-strip
      """
  }

  private func asyncFunction(swiftCode: String, index: Int) -> String {
    return """
      private func userCode_\(index)() async throws -> Any { // test-repl-strip
        \(swiftCode)
      } // test-repl-strip
      @_cdecl("test_\(index)") public func test_\(index)() -> UnsafePointer<CChar>? { // test-repl-strip
        final class _Box: @unchecked Sendable { var value: Result<Any, Error> = .success("()") } // test-repl-strip
        let box = _Box() // test-repl-strip
        let semaphore = DispatchSemaphore(value: 0) // test-repl-strip
        Task { // test-repl-strip
          do { box.value = .success(try await userCode_\(index)()) } // test-repl-strip
          catch { box.value = .failure(error) } // test-repl-strip
          semaphore.signal() // test-repl-strip
        } // test-repl-strip
        semaphore.wait() // test-repl-strip
        let output: String // test-repl-strip
        do { // test-repl-strip
          let result = try box.value.get() // test-repl-strip
          output = "Result:\\n\\(String(describing: result))" // test-repl-strip
        } catch { // test-repl-strip
          output = "Exception:\\n\\(String(describing: error))" // test-repl-strip
        } // test-repl-strip
        return output.withCString { UnsafePointer(strdup($0)) } // test-repl-strip
      } // test-repl-strip
      """
  }

  private func compileSwift(sourcePath: String, outputPath: String, moduleMapPath: String, targetTriple: String, sdkPath: String) throws -> (Int32, String) {
    let swiftcPath = (toolchainPath as NSString).appendingPathComponent("usr/bin/swiftc")
    let swiftc = Process()
    swiftc.executableURL = URL(fileURLWithPath: swiftcPath)
    var environment = ProcessInfo.processInfo.environment
    environment["SDKROOT"] = sdkPath
    swiftc.environment = environment
    swiftc.arguments = [
      sourcePath,
      "-emit-library", "-o", outputPath,
      "-target", targetTriple,
      "-Xfrontend", "-explicit-swift-module-map-file", "-Xfrontend", moduleMapPath,
      "-Xfrontend", "-disable-implicit-swift-modules",
      "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup",
    ]
    let outputPipe = Pipe()
    swiftc.standardOutput = outputPipe
    let errorPipe = Pipe()
    swiftc.standardError = errorPipe
    try swiftc.run()

    // Read both pipes concurrently to avoid deadlock when the OS pipe buffer fills.
    var outputData = Data()
    var errorData = Data()
    let group = DispatchGroup()

    group.enter()
    DispatchQueue.global().async {
      outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
      group.leave()
    }

    group.enter()
    DispatchQueue.global().async {
      errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
      group.leave()
    }

    group.wait()
    swiftc.waitUntilExit()

    let filters: [NSRegularExpression] = [
      try NSRegularExpression(pattern: #"ld: warning: -undefined dynamic_lookup is deprecated.*"#)
    ]

    let sessionPath = sessionDirectory.path
    var filteredLines: [String] = []

    for data in [outputData, errorData] {
      if let output = String(data: data, encoding: .utf8) {
        for line in output.components(separatedBy: "\n") {
          let range = NSRange(line.startIndex..., in: line)
          let filtered = filters.contains { $0.firstMatch(in: line, range: range) != nil }
          if !filtered && !line.isEmpty && !line.contains("// test-repl-strip") {
            filteredLines.append(line.replacingOccurrences(of: sessionPath, with: ""))
          }
        }
      }
    }

    return (swiftc.terminationStatus, filteredLines.joined(separator: "\n"))
  }

  private func printHelp() {
    printStatus(
      "Available commands:",
      "  /help         Show this help message",
      "  /run          Compile and inject the entered Swift code",
      "  /exit         Kill subprocesses and exit",
      "",
      "Enter Swift code line by line, then type /run to execute."
    )
  }

  private func printStatus(_ lines: String...) {
    for line in lines {
      print(line)
    }
    print("")
  }

  // MARK: - Socket Communication

  private func connectToSocket(path: String) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw ValidationError("Failed to create socket")
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
    guard path.utf8.count < maxLength else {
      close(fd)
      throw ValidationError("Socket path too long (\(path.utf8.count) bytes, max \(maxLength - 1)): \(path)")
    }
    _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
      path.withCString { src in
        memcpy(ptr, src, path.utf8.count + 1)
      }
    }

    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    var connected = false
    for _ in 0..<10 {
      let result = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
          connect(fd, sockPtr, size)
        }
      }
      if result == 0 {
        connected = true
        break
      }
      usleep(100_000)
    }

    guard connected else {
      close(fd)
      throw ValidationError("Failed to connect to test process socket at \(path)")
    }

    return fd
  }

  private func sendCommand(dylibPath: String, symbol: String, socketFd: Int32) throws -> [String: Any] {
    let command: [String: String] = ["dylib": dylibPath, "symbol": symbol]
    var data = try JSONSerialization.data(withJSONObject: command)
    data.append(0x0A)
    data.withUnsafeBytes { ptr in
      if let base = ptr.baseAddress {
        _ = write(socketFd, base, ptr.count)
      }
    }

    var responseData = Data()
    var byte: UInt8 = 0
    while read(socketFd, &byte, 1) > 0 {
      if byte == 0x0A { break }
      responseData.append(byte)
    }

    guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
      throw ValidationError("Invalid response from test process")
    }

    return response
  }
}
