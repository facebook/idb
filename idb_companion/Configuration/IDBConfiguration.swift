/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
//  IDBConfiguration.swift
//  idb-Focused
//
//  Created by Nikita Patskov on 20/05/2022.
//

import Foundation

class IDBConfiguration: NSObject {

  @objc static var eventReporter: FBEventReporter = EmptyEventReporter.shared
  @objc static var swiftEventReporter: FBEventReporter = EmptyEventReporter.shared

}
