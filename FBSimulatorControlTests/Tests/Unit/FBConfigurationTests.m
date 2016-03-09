/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlFixtures.h"

@interface FBConfigurationTests : XCTestCase

@end

@implementation FBConfigurationTests

- (NSArray *)serializableConfigurations
{
  return [[[[[[[self.videoConfigurations
    arrayByAddingObjectsFromArray:self.processLaunchConfigurations]
    arrayByAddingObjectsFromArray:self.simulatorConfigurations]
    arrayByAddingObjectsFromArray:self.controlConfigurations]
    arrayByAddingObjectsFromArray:self.launchConfigurations]
    arrayByAddingObjectsFromArray:self.diagnostics]
    arrayByAddingObjectsFromArray:self.logSearchPredicates]
    arrayByAddingObject:self.batchLogSearch];
}

- (NSArray *)deserializableConfigurations
{
  return [[[self appLaunchConfigurations]
    arrayByAddingObjectsFromArray:self.logSearchPredicates]
    arrayByAddingObject:self.batchLogSearch];
}

- (NSArray *)videoConfigurations
{
  return @[
    [[[FBFramebufferVideoConfiguration withOptions:FBFramebufferVideoOptionsAutorecord | FBFramebufferVideoOptionsFinalFrame ] withRoundingMethod:kCMTimeRoundingMethod_RoundTowardZero] withFileType:@"foo"],
    [[[FBFramebufferVideoConfiguration withOptions:FBFramebufferVideoOptionsImmediateFrameStart] withRoundingMethod:kCMTimeRoundingMethod_RoundTowardNegativeInfinity] withFileType:@"bar"]
  ];
}

- (NSArray *)appLaunchConfigurations
{
  return @[
    self.appLaunch1,
    self.appLaunch2,
  ];
}

- (NSArray *)processLaunchConfigurations
{
  return [self.appLaunchConfigurations arrayByAddingObject:self.agentLaunch1];
}

- (NSArray *)simulatorConfigurations
{
  return @[
    FBSimulatorConfiguration.defaultConfiguration,
    FBSimulatorConfiguration.iPhone5,
    FBSimulatorConfiguration.iPad2.iOS_8_3
  ];
}

- (NSArray *)controlConfigurations
{
  return @[
    [FBSimulatorControlConfiguration
      configurationWithDeviceSetPath:nil
      options:FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart],
    [FBSimulatorControlConfiguration
      configurationWithDeviceSetPath:@"/foo/bar"
      options:FBSimulatorManagementOptionsKillAllOnFirstStart | FBSimulatorManagementOptionsKillAllOnFirstStart]
  ];
}

- (NSArray *)launchConfigurations
{
  return @[
    [[[FBSimulatorLaunchConfiguration
      withLocaleNamed:@"en_US"]
      withOptions:FBSimulatorLaunchOptionsShowDebugWindow]
      scale75Percent],
    [[FBSimulatorLaunchConfiguration
      withOptions:FBSimulatorLaunchOptionsUseNSWorkspace]
      scale25Percent]
  ];
}

- (NSArray *)diagnostics
{
  return @[
    [[[[FBDiagnosticBuilder.builder
      updateString:@"FOO"]
      updateShortName:@"BAAAA"]
      updateFileType:@"txt"]
      build],
    [[[[FBDiagnosticBuilder.builder
      updateString:@"BING"]
      updateShortName:@"BONG"]
      updateFileType:@"txt"]
      build],
  ];
}

- (NSArray *)logSearchPredicates
{
  return @[
    [FBLogSearchPredicate substrings:@[@"foo", @"bar", @"baz"]],
    [FBLogSearchPredicate regex:@"(foo|bar|baz)"]
  ];
}

- (FBBatchLogSearch *)batchLogSearch
{
  return [FBBatchLogSearch withMapping:@{
    @[@"log1", @"log2"] : @[[FBLogSearchPredicate substrings:@[@"foo, bar, baz"]]],
    @[@"log3"] : @[[FBLogSearchPredicate regex:@"(foo|bar|baz)"], [FBLogSearchPredicate substrings:@[@"blastoof"]]]
  } error:nil];
}

- (void)testEqualityOfCopy
{
  for (id config in self.serializableConfigurations) {
    id configCopy = [config copy];
    id configCopyCopy = [configCopy copy];
    XCTAssertEqualObjects(config, configCopy);
    XCTAssertEqualObjects(config, configCopyCopy);
    XCTAssertEqualObjects(configCopy, configCopyCopy);
  }
}

- (void)testUnarchiving
{
  for (id config in self.serializableConfigurations) {
    NSData *configData = [NSKeyedArchiver archivedDataWithRootObject:config];
    id configUnarchived = [NSKeyedUnarchiver unarchiveObjectWithData:configData];
    XCTAssertEqualObjects(config, configUnarchived);
  }
}

- (void)testJSONSerialization
{
  for (id config in self.serializableConfigurations) {
    [self assertStringKeysJSONValues:[config jsonSerializableRepresentation]];
  }
}

- (void)testEqualityOfDeserialization
{
  for (id value in self.deserializableConfigurations) {
    id json = [value jsonSerializableRepresentation];
    NSError *error = nil;
    id serializedValue = [[value class] inflateFromJSON:json error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(value, serializedValue);
    XCTAssertEqualObjects(json, [serializedValue jsonSerializableRepresentation]);
  }
}

- (void)assertStringKeysJSONValues:(NSDictionary *)json
{
  NSSet *keyTypes = [NSSet setWithArray:[json.allKeys valueForKey:@"class"]];
  for (Class class in keyTypes) {
    XCTAssertTrue([class isSubclassOfClass:NSString.class]);
  }
  [self assertJSONValues:json.allValues];
}

- (void)assertJSONValues:(NSArray *)json
{
  for (id value in json) {
    if ([value isKindOfClass:NSString.class]) {
      continue;
    }
    if ([value isKindOfClass:NSNumber.class]) {
      continue;
    }
    if ([value isEqual:NSNull.null]) {
      continue;
    }
    if ([value isKindOfClass:NSArray.class]) {
      [self assertJSONValues:value];
      continue;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
      [self assertStringKeysJSONValues:value];
      continue;
    }
    XCTFail(@"%@ is not json encodable", value);
  }
}

@end
