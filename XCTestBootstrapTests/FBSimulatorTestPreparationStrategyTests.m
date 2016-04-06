/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>

#import "FBDeviceOperator.h"
#import "FBFileManager.h"
#import "FBProductBundle.h"
#import "FBSimulatorTestPreparationStrategy.h"
#import "FBTestRunnerConfiguration.h"

@interface FBSimulatorTestPreparationStrategyTests : XCTestCase
@end

@implementation FBSimulatorTestPreparationStrategyTests

+ (BOOL)isGoodConfigurationPath:(NSString *)path
{
  return [path rangeOfString:@"\\/heaven\\/testBundle\\/testBundle-(.*)\\.xctestconfiguration" options:NSRegularExpressionSearch].location != NSNotFound;
}

- (void)testStrategyWithMissingWorkingDirectory
{
  FBSimulatorTestPreparationStrategy *strategy =
  [FBSimulatorTestPreparationStrategy strategyWithTestRunnerBundleID:@""
                                                      testBundlePath:@""
                                                    workingDirectory:nil
                                                         fileManager:nil];
  XCTAssertThrows([strategy prepareTestWithDeviceOperator:[OCMockObject niceMockForProtocol:@protocol(FBDeviceOperator)] error:nil]);
}

- (void)testStrategyWithMissingTestBundlePath
{
  FBSimulatorTestPreparationStrategy *strategy =
  [FBSimulatorTestPreparationStrategy strategyWithTestRunnerBundleID:@""
                                                      testBundlePath:nil
                                                    workingDirectory:@""
                                                         fileManager:nil];
  XCTAssertThrows([strategy prepareTestWithDeviceOperator:[OCMockObject niceMockForProtocol:@protocol(FBDeviceOperator)] error:nil]);
}

- (void)testStrategyWithMissingApplicationPath
{
  FBSimulatorTestPreparationStrategy *strategy =
  [FBSimulatorTestPreparationStrategy strategyWithTestRunnerBundleID:nil
                                                      testBundlePath:@""
                                                    workingDirectory:@""
                                                         fileManager:nil];
  XCTAssertThrows([strategy prepareTestWithDeviceOperator:[OCMockObject niceMockForProtocol:@protocol(FBDeviceOperator)] error:nil]);
}

- (void)testSimulatorPreparation
{
  id xctConfigArg = [OCMArg checkWithBlock:^BOOL(NSString *path){return [self.class isGoodConfigurationPath:path];}];
  NSDictionary *plist =
  @{
    @"CFBundleIdentifier" : @"bundleID",
    @"CFBundleExecutable" : @"exec",
  };

  OCMockObject<FBFileManager> *fileManagerMock = [OCMockObject mockForProtocol:@protocol(FBFileManager)];
  [[[fileManagerMock stub] andReturn:plist] dictionaryWithPath:[OCMArg any]];
  [[[fileManagerMock expect] andReturnValue:@YES] copyItemAtPath:@"/testBundle" toPath:@"/heaven/testBundle" error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] writeData:[OCMArg any] toFile:xctConfigArg options:0 error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock stub] andReturnValue:@YES] ignoringNonObjectArgs] createDirectoryAtPath:@"/heaven" withIntermediateDirectories:YES attributes:[OCMArg any] error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock stub] andReturnValue:@NO] ignoringNonObjectArgs] fileExistsAtPath:[OCMArg any]];

  FBProductBundle *productBundle =
  [[[FBProductBundleBuilder builderWithFileManager:fileManagerMock]
    withBundlePath:@"/app"]
   build];

  OCMockObject<FBDeviceOperator> *deviceOperatorMock = [OCMockObject mockForProtocol:@protocol(FBDeviceOperator)];
  [[[deviceOperatorMock expect] andReturn:productBundle] applicationBundleWithBundleID:@"bundleId" error:[OCMArg anyObjectRef]];

  FBSimulatorTestPreparationStrategy *strategy =
  [FBSimulatorTestPreparationStrategy strategyWithTestRunnerBundleID:@"bundleId"
                                                      testBundlePath:@"/testBundle"
                                                    workingDirectory:@"/heaven"
                                                         fileManager:fileManagerMock];
  FBTestRunnerConfiguration *configuration = [strategy prepareTestWithDeviceOperator:deviceOperatorMock error:nil];

  NSDictionary *env = configuration.launchEnvironment;
  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.testRunner);
  XCTAssertNotNil(configuration.launchArguments);
  XCTAssertNotNil(env);
  XCTAssertEqualObjects(env[@"AppTargetLocation"], @"/app/exec");
  XCTAssertEqualObjects(env[@"TestBundleLocation"], @"/heaven/testBundle");
  XCTAssertEqualObjects(env[@"XCInjectBundle"], @"/heaven/testBundle");
  XCTAssertEqualObjects(env[@"XCInjectBundleInto"], @"/app/exec");
  XCTAssertNotNil(env[@"DYLD_INSERT_LIBRARIES"]);
  XCTAssertTrue([self.class isGoodConfigurationPath:configuration.launchEnvironment[@"XCTestConfigurationFilePath"]],
                @"XCTestConfigurationFilePath should be like /heaven/testBundle/testBundle-[UDID].xctestconfiguration but is %@",
                env[@"XCTestConfigurationFilePath"]
                );
  [fileManagerMock verify];
  [deviceOperatorMock verify];
}

@end
