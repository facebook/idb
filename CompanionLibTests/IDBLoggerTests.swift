/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency @testable import CompanionLib
import Foundation
import Testing

// Serialized because the factory installs its result as
// ControlCoreGlobalConfiguration.defaultLogger, which is process-global.
@Suite(.serialized)
struct IDBLoggerTests {

  private func userDefaults(logFilePath: String? = nil, logLevel: String? = nil) -> UserDefaults {
    let defaults = UserDefaults(suiteName: "idb-logger-tests-\(UUID().uuidString)")!
    if let logFilePath {
      defaults.set(logFilePath, forKey: "-log-file-path")
    }
    if let logLevel {
      defaults.set(logLevel, forKey: "-log-level")
    }
    return defaults
  }

  private func temporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("idb-logger-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test
  func logsOnlyToTheSystemLoggerWithoutALogFilePath() throws {
    let logger = try IDBLogger.logger(withUserDefaults: userDefaults())
    #expect(logger.loggers.count == 1)
  }

  @Test
  func writesToTheRequestedLogFile() throws {
    let logFileURL = try temporaryDirectory().appendingPathComponent("companion.log")
    let logger = try IDBLogger.logger(withUserDefaults: userDefaults(logFilePath: logFileURL.path))
    logger.log("a line only this test writes")

    let contents = try String(contentsOf: logFileURL, encoding: .utf8)
    #expect(contents.contains("a line only this test writes"))
  }

  @Test
  func createsTheDirectoryContainingTheLogFile() throws {
    let logFileURL = try temporaryDirectory()
      .appendingPathComponent("nested")
      .appendingPathComponent("deeper")
      .appendingPathComponent("companion.log")
    _ = try IDBLogger.logger(withUserDefaults: userDefaults(logFilePath: logFileURL.path))

    #expect(FileManager.default.fileExists(atPath: logFileURL.path))
  }

  @Test
  func createsTheLogFileWithTheModeAnOrdinaryFileGets() throws {
    let directoryURL = try temporaryDirectory()
    let logFileURL = directoryURL.appendingPathComponent("companion.log")
    _ = try IDBLogger.logger(withUserDefaults: userDefaults(logFilePath: logFileURL.path))

    // Compared against a 0644 file this test creates itself rather than against the literal,
    // because the umask clears bits from both alike and the runner's is not ours to assume.
    let referenceURL = directoryURL.appendingPathComponent("reference")
    let referenceDescriptor = open(referenceURL.path, O_WRONLY | O_CREAT, 0o644)
    try #require(referenceDescriptor >= 0)
    close(referenceDescriptor)

    let logMode = try FileManager.default.attributesOfItem(atPath: logFileURL.path)[.posixPermissions] as? Int
    let referenceMode = try FileManager.default.attributesOfItem(atPath: referenceURL.path)[.posixPermissions] as? Int
    #expect(logMode == referenceMode)
  }

  @Test
  func throwsWhenTheLogDirectoryCannotBeCreated() throws {
    // A regular file where the log's parent directory has to go: createDirectory cannot
    // replace it, so the failure lands before the file is ever opened.
    let blockingFileURL = try temporaryDirectory().appendingPathComponent("not-a-directory")
    #expect(FileManager.default.createFile(atPath: blockingFileURL.path, contents: Data()))
    let logFilePath = blockingFileURL.appendingPathComponent("companion.log").path

    #expect(throws: IDBLoggerError.self) {
      _ = try IDBLogger.logger(withUserDefaults: userDefaults(logFilePath: logFilePath))
    }
  }

  @Test
  func throwsWhenTheLogFileCannotBeOpened() throws {
    // The log path is itself a directory, so open(2) fails with EISDIR after the
    // containing directory has been created successfully.
    let directoryURL = try temporaryDirectory().appendingPathComponent("companion.log")
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

    do {
      _ = try IDBLogger.logger(withUserDefaults: userDefaults(logFilePath: directoryURL.path))
      Issue.record("Expected the logger factory to throw")
    } catch let error as IDBLoggerError {
      guard case let .logFileOpenFailed(path, code) = error else {
        Issue.record("Expected logFileOpenFailed, got \(error)")
        return
      }
      #expect(path == directoryURL.path)
      #expect(code == EISDIR)
    }
  }
}
