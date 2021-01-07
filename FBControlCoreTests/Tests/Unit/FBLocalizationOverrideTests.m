/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreValueTestCase.h"

@interface FBLocalizationOverrideTests : FBControlCoreValueTestCase

@end

@implementation FBLocalizationOverrideTests

- (void)testArguments
{
  FBLocalizationOverride *override = [FBLocalizationOverride withLocale:[NSLocale localeWithLocaleIdentifier:@"es_ES"]];
  XCTAssertEqualObjects(override.arguments, (@[@"-AppleLocale", @"es_ES", @"-AppleLanguages", @"(es)"]));
}

- (void)testEnvironment
{
  FBLocalizationOverride *override = [FBLocalizationOverride withLocale:[NSLocale localeWithLocaleIdentifier:@"es_ES"]];
  NSDictionary *defaults = override.defaultsDictionary;
  XCTAssertEqualObjects(defaults[@"AppleLocale"], @"es_ES");
  XCTAssertEqualObjects(defaults[@"AppleLanguages"], (@[@"es"]));
}

@end
