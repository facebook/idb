/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import IDBGRPCSwift

// Convenient extractions of items from certain requests

protocol DataExtractable {
  func extractDataFrame() -> Data?
}

protocol PayloadExtractable: DataExtractable {
  func extractPayload() -> Idb_Payload?
}

extension Idb_InstallRequest: PayloadExtractable {
  func extractPayload() -> Idb_Payload? {
    switch value {
    case .payload(let payload):
      return payload
    default:
      return nil
    }
  }
}

extension Idb_PushRequest: PayloadExtractable {
  func extractPayload() -> Idb_Payload? {
    switch value {
    case .payload(let payload):
      return payload
    default:
      return nil
    }
  }
}

extension Idb_AddMediaRequest: PayloadExtractable {
  func extractPayload() -> Idb_Payload? {
    if hasPayload {
      return payload
    }
    return nil
  }
}

extension PayloadExtractable {
  func extractDataFrame() -> Data? {
    extractPayload()?.extractDataFrame()
  }
}

extension Idb_Payload: DataExtractable {
  func extractDataFrame() -> Data? {
    switch source {
    case let .data(data):
      return data
    default:
      return nil
    }
  }
}
