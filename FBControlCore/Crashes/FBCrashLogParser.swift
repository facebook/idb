/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBCrashLogParser)
public protocol FBCrashLogParser: NSObjectProtocol {
  @objc(parseCrashLogFromString:executablePathOut:identifierOut:processNameOut:parentProcessNameOut:processIdentifierOut:parentProcessIdentifierOut:dateOut:exceptionDescription:crashedThreadDescription:error:)
  func parseCrashLog(from str: String, executablePathOut: AutoreleasingUnsafeMutablePointer<NSString>, identifierOut: AutoreleasingUnsafeMutablePointer<NSString>, processNameOut: AutoreleasingUnsafeMutablePointer<NSString>, parentProcessNameOut: AutoreleasingUnsafeMutablePointer<NSString>, processIdentifierOut: UnsafeMutablePointer<pid_t>, parentProcessIdentifierOut: UnsafeMutablePointer<pid_t>, dateOut: AutoreleasingUnsafeMutablePointer<NSDate>, exceptionDescription: AutoreleasingUnsafeMutablePointer<NSString>, crashedThreadDescription: AutoreleasingUnsafeMutablePointer<NSString>, error: NSErrorPointer)
}

/// .ips file for macOS 12+ is two concatenated json strings.
/// 1st is metadata json, second is content json. Some of the fields from metadata repeats in content json.
/// Considering the facts that:
/// 1. The layout can be changed by apple easily
/// 2. Json structure itself can be easily changed
/// 3. Crashes is not often happening operation of idb
/// we prefer reliability over performance gain here and parse all json strings finding the fields that we need in all of json entries
@objc(FBConcatedJSONCrashLogParser)
public class FBConcatedJSONCrashLogParser: NSObject, FBCrashLogParser {

  public func parseCrashLog(from str: String, executablePathOut: AutoreleasingUnsafeMutablePointer<NSString>, identifierOut: AutoreleasingUnsafeMutablePointer<NSString>, processNameOut: AutoreleasingUnsafeMutablePointer<NSString>, parentProcessNameOut: AutoreleasingUnsafeMutablePointer<NSString>, processIdentifierOut: UnsafeMutablePointer<pid_t>, parentProcessIdentifierOut: UnsafeMutablePointer<pid_t>, dateOut: AutoreleasingUnsafeMutablePointer<NSDate>, exceptionDescription: AutoreleasingUnsafeMutablePointer<NSString>, crashedThreadDescription: AutoreleasingUnsafeMutablePointer<NSString>, error: NSErrorPointer) {
    let parsedReport: [String: Any]
    do {
      parsedReport = try FBConcatedJsonParser.parseConcatenatedJSON(from: str)
    } catch let parseError {
      error?.pointee = parseError as NSError
      return
    }

    if let procPath = parsedReport["procPath"] as? String {
      executablePathOut.pointee = procPath as NSString
    }

    // Name and identifier is the same thing
    if let procName = parsedReport["procName"] as? String {
      processNameOut.pointee = procName as NSString
      identifierOut.pointee = procName as NSString
    }
    if let pid = parsedReport["pid"] as? NSNumber {
      processIdentifierOut.pointee = pid.int32Value
    }

    if let parentProc = parsedReport["parentProc"] as? String {
      parentProcessNameOut.pointee = parentProc as NSString
    }
    if let parentPid = parsedReport["parentPid"] as? NSNumber {
      parentProcessIdentifierOut.pointee = parentPid.int32Value
    }
    if let captureTime = parsedReport["captureTime"] as? String {
      if let date = FBCrashLog.dateFormatter().date(from: captureTime) {
        dateOut.pointee = date as NSDate
      }
    }

    if let exceptionDictionary = parsedReport["exception"] as? [String: Any] {
      var exceptionDescriptionMutable = ""
      if let exceptionType = exceptionDictionary["type"] as? String {
        exceptionDescriptionMutable += exceptionType
      }
      if let exceptionSignal = exceptionDictionary["signal"] as? String {
        exceptionDescriptionMutable += " " + exceptionSignal
      }
      if let exceptionSubtype = exceptionDictionary["subtype"] as? String {
        exceptionDescriptionMutable += " " + exceptionSubtype
      }
      exceptionDescription.pointee = exceptionDescriptionMutable as NSString
    }

    var imageNames: [String] = []
    if let imageDictionaries = parsedReport["usedImages"] as? [[String: Any]] {
      for imageDictionary in imageDictionaries {
        if let imageName = imageDictionary["name"] as? String {
          imageNames.append(imageName)
        }
      }
    }

    if let threads = parsedReport["threads"] as? [[String: Any]] {
      for threadDictionary in threads {
        guard (threadDictionary["triggered"] as? NSNumber)?.boolValue == true else {
          continue
        }
        if let frames = threadDictionary["frames"] as? [[String: Any]] {
          var crashedThreadDescriptionMutable = ""
          for frameDictionary in frames {
            let imageIndex = (frameDictionary["imageIndex"] as? NSNumber)?.uintValue ?? 0
            if imageNames.count > Int(imageIndex) {
              var imageNameString = imageNames[Int(imageIndex)]
              if imageNameString.count < 30 {
                imageNameString = imageNameString.padding(toLength: 30, withPad: " ", startingAt: 0)
              }
              crashedThreadDescriptionMutable += imageNameString + "\t"
            }
            if let symbol = frameDictionary["symbol"] as? String {
              crashedThreadDescriptionMutable += symbol + "\n"
            }
          }
          crashedThreadDescription.pointee = crashedThreadDescriptionMutable.trimmingCharacters(in: .whitespacesAndNewlines) as NSString
        }
        break
      }
    }
  }
}

/// This parser handles old plain text implementation of crash results
@objc(FBPlainTextCrashLogParser)
public class FBPlainTextCrashLogParser: NSObject, FBCrashLogParser {

  private static let maxLineSearch: UInt = 20

  public func parseCrashLog(from str: String, executablePathOut: AutoreleasingUnsafeMutablePointer<NSString>, identifierOut: AutoreleasingUnsafeMutablePointer<NSString>, processNameOut: AutoreleasingUnsafeMutablePointer<NSString>, parentProcessNameOut: AutoreleasingUnsafeMutablePointer<NSString>, processIdentifierOut: UnsafeMutablePointer<pid_t>, parentProcessIdentifierOut: UnsafeMutablePointer<pid_t>, dateOut: AutoreleasingUnsafeMutablePointer<NSDate>, exceptionDescription: AutoreleasingUnsafeMutablePointer<NSString>, crashedThreadDescription: AutoreleasingUnsafeMutablePointer<NSString>, error: NSErrorPointer) {
    let nsStr = str as NSString
    let length = nsStr.length
    var paraStart: Int = 0
    var paraEnd: Int = 0
    var contentsEnd: Int = 0
    var linesParsed: UInt = 0

    while paraEnd < length && linesParsed < FBPlainTextCrashLogParser.maxLineSearch {
      linesParsed += 1
      nsStr.getParagraphStart(&paraStart, end: &paraEnd, contentsEnd: &contentsEnd, for: NSRange(location: paraEnd, length: 0))
      let line = nsStr.substring(with: NSRange(location: paraStart, length: contentsEnd - paraStart))

      if let match = parseProcessLine(line) {
        processNameOut.pointee = match.name as NSString
        processIdentifierOut.pointee = match.pid
        continue
      }
      if let identifier = parseIdentifierLine(line) {
        identifierOut.pointee = identifier as NSString
        continue
      }
      if let match = parseParentProcessLine(line) {
        parentProcessNameOut.pointee = match.name as NSString
        parentProcessIdentifierOut.pointee = match.pid
        continue
      }
      if let path = parsePathLine(line) {
        executablePathOut.pointee = path as NSString
        continue
      }
      if let date = parseDateLine(line) {
        dateOut.pointee = date as NSDate
        continue
      }
    }
  }

  // MARK: Private

  private func parseProcessLine(_ line: String) -> (name: String, pid: pid_t)? {
    let scanner = Scanner(string: line)
    guard scanner.scanString("Process:") != nil,
      let name = scanner.scanUpToString("["),
      scanner.scanString("[") != nil
    else {
      return nil
    }
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    guard let pid = scanner.scanInt32() else {
      return (trimmedName, 0)
    }
    return (trimmedName, pid)
  }

  private func parseIdentifierLine(_ line: String) -> String? {
    let scanner = Scanner(string: line)
    guard scanner.scanString("Identifier:") != nil else { return nil }
    let remaining = String(line[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)
    let components = remaining.components(separatedBy: .whitespaces)
    return components.first
  }

  private func parseParentProcessLine(_ line: String) -> (name: String, pid: pid_t)? {
    let scanner = Scanner(string: line)
    guard scanner.scanString("Parent Process:") != nil,
      let name = scanner.scanUpToString("["),
      scanner.scanString("[") != nil
    else {
      return nil
    }
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    guard let pid = scanner.scanInt32() else {
      return (trimmedName, 0)
    }
    return (trimmedName, pid)
  }

  private func parsePathLine(_ line: String) -> String? {
    let scanner = Scanner(string: line)
    guard scanner.scanString("Path:") != nil else { return nil }
    let remaining = String(line[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)
    let components = remaining.components(separatedBy: .whitespaces)
    return components.first
  }

  private func parseDateLine(_ line: String) -> Date? {
    let scanner = Scanner(string: line)
    guard scanner.scanString("Date/Time:") != nil else { return nil }
    let remaining = String(line[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)
    return FBCrashLog.dateFormatter().date(from: remaining)
  }
}
