/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension Help: CustomStringConvertible {
  public var description: String {
    return CLI.parser.description
  }
}
