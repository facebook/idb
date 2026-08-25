/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The kind of process that has crashed, with the member names the `NS_OPTIONS` importer produced.
public struct FBCrashLogInfoProcessType: OptionSet, Sendable {
  public let rawValue: UInt

  public init(rawValue: UInt) {
    self.rawValue = rawValue
  }

  /// A process that is part of the operating system runtime.
  public static let system = FBCrashLogInfoProcessType(rawValue: 1 << 0)
  /// A process that is an application.
  public static let application = FBCrashLogInfoProcessType(rawValue: 1 << 1)
  /// A process that is neither an application nor part of the operating system runtime.
  public static let custom = FBCrashLogInfoProcessType(rawValue: 1 << 2)
}

@objc(FBCrashLog)
public class FBCrashLog: NSObject, NSCopying {

  @objc public let info: FBCrashLogInfo
  @objc public let contents: String

  @objc
  public init(info: FBCrashLogInfo, contents: String) {
    self.info = info
    self.contents = contents
    super.init()
  }

  // MARK: NSObject

  public override var description: String {
    "Crash Info: \(info) \n Crash Report: \(contents)\n"
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    // Is immutable
    self
  }

  // MARK: Public

  @objc
  public class func dateFormatter() -> DateFormatter {
    FBCrashLog_dateFormatter
  }
}

private let FBCrashLog_dateFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
  formatter.isLenient = true
  formatter.locale = Locale(identifier: "en_US")
  return formatter
}()

/// The ways crash-log reading and parsing can fail, as data rather than assembled strings.
public enum FBCrashLogError: Error {
  case fileDoesNotExist(path: String)
  case fileNotReadable(path: String)
  case dataReadFailed(path: String, underlying: Error)
  case fileEmpty(path: String)
  case stringExtractionFailed(path: String)
  case readFailed(path: String, underlying: Error)
  case parseFailed(underlying: Error)
  case missingField(field: String)
}

extension FBCrashLogError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .fileDoesNotExist(path):
      return "File does not exist at given crash path: \(path)"
    case let .fileNotReadable(path):
      return "Crash file at \(path) is not readable"
    case let .dataReadFailed(path, _):
      return "Could not read data from \(path)"
    case let .fileEmpty(path):
      return "Crash file at \(path) is empty"
    case let .stringExtractionFailed(path):
      return "Could not extract string from \(path)"
    case let .readFailed(path, _):
      return "Failed to read crash log at path \(path)"
    case let .parseFailed(underlying):
      return "Could not parse crash string \(underlying)"
    case let .missingField(field):
      return "Missing \(field) in crash log"
    }
  }
}

@objc(FBCrashLogInfo)
public class FBCrashLogInfo: NSObject, NSCopying {

  // MARK: Properties

  @objc public let crashPath: String
  @objc public let executablePath: String
  @objc public let identifier: String
  @objc public let processName: String
  @objc public let processIdentifier: pid_t
  @objc public let parentProcessName: String
  @objc public let parentProcessIdentifier: pid_t
  @objc public let date: Date
  public let processType: FBCrashLogInfoProcessType
  @objc public let exceptionDescription: String?
  @objc public let crashedThreadDescription: String?

  @objc public var name: String {
    (crashPath as NSString).lastPathComponent
  }

  // MARK: Initializers

  public init(
    crashPath: String,
    executablePath: String,
    identifier: String,
    processName: String,
    processIdentifier: pid_t,
    parentProcessName: String,
    parentProcessIdentifier: pid_t,
    date: Date,
    processType: FBCrashLogInfoProcessType,
    exceptionDescription: String?,
    crashedThreadDescription: String?
  ) {
    self.crashPath = crashPath
    self.executablePath = executablePath
    self.identifier = identifier
    self.processName = processName
    self.processIdentifier = processIdentifier
    self.parentProcessName = parentProcessName
    self.parentProcessIdentifier = parentProcessIdentifier
    self.date = date
    self.processType = processType
    self.exceptionDescription = exceptionDescription
    self.crashedThreadDescription = crashedThreadDescription
    super.init()
  }

  // MARK: Factory Methods

  @objc(fromCrashLogAtPath:error:)
  public class func fromCrashLog(atPath crashPath: String) throws -> FBCrashLogInfo {
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: crashPath) {
      throw FBCrashLogError.fileDoesNotExist(path: crashPath)
    }
    if !fileManager.isReadableFile(atPath: crashPath) {
      throw FBCrashLogError.fileNotReadable(path: crashPath)
    }
    let crashFileData: Data
    do {
      crashFileData = try Data(contentsOf: URL(fileURLWithPath: crashPath))
    } catch {
      throw FBCrashLogError.dataReadFailed(path: crashPath, underlying: error)
    }
    if crashFileData.isEmpty {
      throw FBCrashLogError.fileEmpty(path: crashPath)
    }

    guard let crashString = String(data: crashFileData, encoding: .utf8) else {
      throw FBCrashLogError.stringExtractionFailed(path: crashPath)
    }

    let parser = getPreferredCrashLogParser(forCrashString: crashString)
    return try fromCrashLogString(crashString, crashPath: crashPath, parser: parser)
  }

  @objc(isParsableCrashLog:)
  public class func isParsableCrashLog(_ data: Data) -> Bool {
    #if canImport(Darwin)
    guard let crashString = String(data: data, encoding: .utf8) else {
      return false
    }
    let parser = getPreferredCrashLogParser(forCrashString: crashString)
    do {
      _ = try fromCrashLogString(crashString, crashPath: "", parser: parser)
      return true
    } catch {
      return false
    }
    #else
    return false
    #endif
  }

  // MARK: NSObject

  public override var description: String {
    "Identifier \(identifier) | Executable Path \(executablePath) | Process \(processName) | pid \(processIdentifier) | Parent \(parentProcessName) | ppid \(parentProcessIdentifier) | Date \(date) | Path \(crashPath) | Exception: \(exceptionDescription ?? "nil") | Trace: \(crashedThreadDescription ?? "nil")"
  }

  // MARK: NSCopying

  public func copy(with zone: NSZone? = nil) -> Any {
    // Is immutable
    self
  }

  // MARK: Public Methods

  @objc(loadRawCrashLogStringWithError:)
  public func loadRawCrashLogString() throws -> String {
    try String(contentsOfFile: crashPath, encoding: .utf8)
  }

  // MARK: Bulk Collection

  @objc(crashInfoAfterDate:logger:)
  public class func crashInfo(afterDate date: Date, logger: FBControlCoreLogger?) -> [FBCrashLogInfo] {
    var allCrashInfos: [FBCrashLogInfo] = []

    for basePath in diagnosticReportsPaths {
      let fileNames = (try? FileManager.default.contentsOfDirectory(atPath: basePath)) ?? []
      let predicate = predicateForFiles(withBasePath: basePath, afterDate: date, withExtensions: ["crash", "ips"])
      let crashInfos = FBConcurrentCollectionOperations.filterMap(
        fileNames as [Any],
        predicate: predicate,
        map: { item -> Any in
          guard let fileName = item as? String else {
            return NSNull()
          }
          let path = (basePath as NSString).appendingPathComponent(fileName)
          do {
            return try FBCrashLogInfo.fromCrashLog(atPath: path)
          } catch {
            logger?.log("Error parsing log \(error)")
            return NSNull()
          }
        }
      )
      allCrashInfos.append(contentsOf: crashInfos.compactMap { $0 as? FBCrashLogInfo })
    }

    return allCrashInfos
  }

  // MARK: Contents

  @objc(obtainCrashLogWithError:)
  public func obtainCrashLog() throws -> FBCrashLog {
    let contents: String
    do {
      contents = try loadRawCrashLogString()
    } catch {
      throw FBCrashLogError.readFailed(path: crashPath, underlying: error)
    }
    return FBCrashLog(info: self, contents: contents)
  }

  // MARK: Predicates

  @objc(predicateForCrashLogsWithProcessID:)
  public class func predicateForCrashLogs(withProcessID processID: pid_t) -> NSPredicate {
    NSPredicate { evaluatedObject, _ in
      guard let crashLog = evaluatedObject as? FBCrashLogInfo else { return false }
      return crashLog.processIdentifier == processID
    }
  }

  @objc(predicateNewerThanDate:)
  public class func predicateNewer(thanDate date: Date) -> NSPredicate {
    NSPredicate { evaluatedObject, _ in
      guard let crashLog = evaluatedObject as? FBCrashLogInfo else { return false }
      return date.compare(crashLog.date) == .orderedAscending
    }
  }

  @objc(predicateOlderThanDate:)
  public class func predicateOlder(thanDate date: Date) -> NSPredicate {
    NSCompoundPredicate(notPredicateWithSubpredicate: predicateNewer(thanDate: date))
  }

  @objc(predicateForIdentifier:)
  public class func predicate(forIdentifier identifier: String) -> NSPredicate {
    NSPredicate { evaluatedObject, _ in
      guard let crashLog = evaluatedObject as? FBCrashLogInfo else { return false }
      return identifier == crashLog.identifier
    }
  }

  @objc(predicateForName:)
  public class func predicate(forName name: String) -> NSPredicate {
    NSPredicate { evaluatedObject, _ in
      guard let crashLog = evaluatedObject as? FBCrashLogInfo else { return false }
      return name == crashLog.name
    }
  }

  @objc(predicateForExecutablePathContains:)
  public class func predicate(forExecutablePathContains contains: String) -> NSPredicate {
    NSPredicate { evaluatedObject, _ in
      guard let crashLog = evaluatedObject as? FBCrashLogInfo else { return false }
      return crashLog.executablePath.contains(contains)
    }
  }

  // MARK: Helpers

  @objc public class var diagnosticReportsPaths: [String] {
    [
      (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/DiagnosticReports"),
      "/Library/Logs/DiagnosticReports",
    ]
  }

  // MARK: Private

  private class func getPreferredCrashLogParser(forCrashString crashString: String) -> FBCrashLogParser {
    if !crashString.isEmpty && crashString.first == "{" {
      return FBConcatedJSONCrashLogParser()
    } else {
      return FBPlainTextCrashLogParser()
    }
  }

  private class func fromCrashLogString(_ crashString: String, crashPath: String, parser: FBCrashLogParser) throws -> FBCrashLogInfo {
    var executablePath: NSString = NSString()
    var identifier: NSString = NSString()
    var processName: NSString = NSString()
    var parentProcessName: NSString = NSString()
    var processIdentifier: pid_t = -1
    var parentProcessIdentifier: pid_t = -1
    var date: NSDate = NSDate()
    var exceptionDescription: NSString = NSString()
    var crashedThreadDescription: NSString = NSString()

    var parseError: NSError?
    parser.parseCrashLog(
      from: crashString,
      executablePathOut: &executablePath,
      identifierOut: &identifier,
      processNameOut: &processName,
      parentProcessNameOut: &parentProcessName,
      processIdentifierOut: &processIdentifier,
      parentProcessIdentifierOut: &parentProcessIdentifier,
      dateOut: &date,
      exceptionDescription: &exceptionDescription,
      crashedThreadDescription: &crashedThreadDescription,
      error: &parseError
    )

    if let parseError {
      throw FBCrashLogError.parseFailed(underlying: parseError)
    }

    let processNameStr = processName as String
    if processNameStr.isEmpty {
      throw FBCrashLogError.missingField(field: "process name")
    }
    let identifierStr = identifier as String
    if identifierStr.isEmpty {
      throw FBCrashLogError.missingField(field: "identifier")
    }
    let parentProcessNameStr = parentProcessName as String
    if parentProcessNameStr.isEmpty {
      throw FBCrashLogError.missingField(field: "parent process name")
    }
    let executablePathStr = executablePath as String
    if executablePathStr.isEmpty {
      throw FBCrashLogError.missingField(field: "executable path")
    }
    if processIdentifier == -1 {
      throw FBCrashLogError.missingField(field: "process identifier")
    }
    if parentProcessIdentifier == -1 {
      throw FBCrashLogError.missingField(field: "parent process identifier")
    }

    let processType = self.processType(forExecutablePath: executablePathStr)

    let exceptionDescStr = exceptionDescription as String
    let crashedThreadDescStr = crashedThreadDescription as String

    return FBCrashLogInfo(
      crashPath: crashPath,
      executablePath: executablePathStr,
      identifier: identifierStr,
      processName: processNameStr,
      processIdentifier: processIdentifier,
      parentProcessName: parentProcessNameStr,
      parentProcessIdentifier: parentProcessIdentifier,
      date: date as Date,
      processType: processType,
      exceptionDescription: exceptionDescStr.isEmpty ? nil : exceptionDescStr,
      crashedThreadDescription: crashedThreadDescStr.isEmpty ? nil : crashedThreadDescStr
    )
  }

  private class func processType(forExecutablePath executablePath: String) -> FBCrashLogInfoProcessType {
    if executablePath.contains("Platforms/iPhoneSimulator.platform") {
      return .system
    }
    if executablePath.contains(".app") {
      return .application
    }
    return .custom
  }

  private class func predicateForFiles(withBasePath basePath: String, afterDate date: Date, withExtensions extensions: [String]) -> NSPredicate {
    let fileManager = FileManager.default
    let datePredicate: NSPredicate
    datePredicate = NSPredicate { evaluatedObject, _ in
      guard let fileName = evaluatedObject as? String else { return false }
      let path = (basePath as NSString).appendingPathComponent(fileName)
      guard let attributes = try? fileManager.attributesOfItem(atPath: path),
        let modDate = attributes[.modificationDate] as? Date
      else {
        return false
      }
      return modDate.compare(date) != .orderedAscending
    }
    return NSCompoundPredicate(andPredicateWithSubpredicates: [
      NSPredicate(format: "pathExtension in %@", extensions),
      datePredicate,
    ])
  }
}
