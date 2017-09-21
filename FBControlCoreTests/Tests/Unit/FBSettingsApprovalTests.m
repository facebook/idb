/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreValueTestCase.h"

@interface FBSettingsApprovalTests : FBControlCoreValueTestCase

@end

@implementation FBSettingsApprovalTests

+ (NSArray<FBSettingsApproval *> *)approvals
{
  return @[
     [FBSettingsApproval approvalWithBundleIDs:@[@"com.foo.bar", @"bing.bong"] services:@[FBSettingsApprovalServiceContacts]],
     [FBSettingsApproval approvalWithBundleIDs:@[@"com.foo.bar"] services:@[FBSettingsApprovalServiceCamera, FBSettingsApprovalServiceLocation]],
   ];
}

- (void)testValueSemantics
{
  NSArray<FBSettingsApproval *> *approvals = FBSettingsApprovalTests.approvals;
  [self assertEqualityOfCopy:approvals];
  [self assertJSONSerialization:approvals];
  [self assertJSONDeserialization:approvals];
}

@end
