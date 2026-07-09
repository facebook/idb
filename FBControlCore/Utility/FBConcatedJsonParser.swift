/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBConcatedJsonParser)
public final class FBConcatedJsonParser: NSObject {

  @objc(parseConcatenatedJSONFromString:error:)
  public class func parseConcatenatedJSON(from str: String) throws -> [String: Any] {
    var bracketCounter = 0
    var characterEscaped = false
    var inString = false
    var parseError: Error?

    let concatenatedJson = NSMutableDictionary()
    var json = ""

    str.enumerateSubstrings(
      in: str.startIndex..<str.endIndex,
      options: .byComposedCharacterSequences
    ) { substring, _, _, stop in
      guard let c = substring else { return }

      let escaped = characterEscaped
      characterEscaped = false

      if escaped {
        json.append(c)
        return
      }

      if !inString {
        if c == "\n" { return }
        if c == "{" {
          bracketCounter += 1
        } else if c == "}" {
          bracketCounter -= 1
        }
      }

      if c == "\\" {
        characterEscaped = true
      }
      if c == "\"" {
        inString = !inString
      }

      json.append(c)

      if bracketCounter == 0 {
        do {
          guard let data = json.data(using: .utf8) else {
            stop = true
            return
          }
          let parsed = try JSONSerialization.jsonObject(with: data, options: [])
          guard let dict = parsed as? [String: Any] else {
            stop = true
            return
          }
          concatenatedJson.addEntries(from: dict)
        } catch {
          parseError = error
          stop = true
        }
        json = ""
      }
    }

    if let error = parseError {
      throw error
    }

    return concatenatedJson as! [String: Any]
  }
}
