/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ContactsService.h"
#import "ContactsService+Testing.h"

#if __has_include(<SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>)
 #import <SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>
#else
 #import "SimulatorFrameworkBridgeSupport-Swift.h"
#endif

int FBContactsClearWithStore(CNContactStore *store, CNSaveRequest *(^makeSaveRequest)(void))
{
  return (int)[ContactsServiceStaticFuncs clearWithStore:store makeSaveRequest:makeSaveRequest];
}

int handleContactsAction(NSString *action)
{
  return (int)[ContactsServiceStaticFuncs handleContactsAction:action ?: @"(null)"];
}
