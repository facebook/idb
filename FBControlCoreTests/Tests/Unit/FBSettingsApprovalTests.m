/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
