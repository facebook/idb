// Copyright 2004-present Facebook. All Rights Reserved.

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>

#import "FBDeviceOperator.h"
#import "FBDeviceTestPreparationStrategy.h"
#import "FBFileManager.h"
#import "FBTestRunnerConfiguration.h"

@interface FBDeviceTestPreparationStrategyTests : XCTestCase
@end

@implementation FBDeviceTestPreparationStrategyTests

+ (BOOL)isGoodConfigurationPath:(NSString *)path pattern:(NSString *)pattern
{
  return [path rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

- (void)testStrategyWithMissingAppPath
{
  FBDeviceTestPreparationStrategy *strategy =
  [FBDeviceTestPreparationStrategy strategyWithApplicationPath:nil
                                           applicationDataPath:@"/appData"
                                                testBundlePath:@"/testBundle"
   ];
  XCTAssertThrows([strategy prepareTestWithDeviceOperator:[OCMockObject niceMockForProtocol:@protocol(FBDeviceOperator)] error:nil]);
}

- (void)testStrategyWithMissingAppData
{
  FBDeviceTestPreparationStrategy *strategy =
  [FBDeviceTestPreparationStrategy strategyWithApplicationPath:@"/app"
                                           applicationDataPath:nil
                                                testBundlePath:@"/testBundle"
   ];
  XCTAssertThrows([strategy prepareTestWithDeviceOperator:[OCMockObject niceMockForProtocol:@protocol(FBDeviceOperator)] error:nil]);
}

- (void)testStrategyWithMissingTestBundle
{
  FBDeviceTestPreparationStrategy *strategy =
  [FBDeviceTestPreparationStrategy strategyWithApplicationPath:@"/app"
                                           applicationDataPath:@"/appData"
                                                testBundlePath:nil
   ];
  XCTAssertThrows([strategy prepareTestWithDeviceOperator:[OCMockObject niceMockForProtocol:@protocol(FBDeviceOperator)] error:nil]);
}

- (void)testDevicePreparation
{
  NSDictionary *plist =
  @{
    @"CFBundleIdentifier" : @"bundleID",
    @"CFBundleExecutable" : @"exec",
  };

  OCMockObject<FBFileManager> *fileManagerMock = [OCMockObject mockForProtocol:@protocol(FBFileManager)];
  [[[fileManagerMock stub] andReturn:plist] dictionaryWithPath:[OCMArg any]];

  id localConfigArg = [OCMArg checkWithBlock:^BOOL(NSString *path){return [self.class isGoodConfigurationPath:path pattern:@"\\/testBundle\\/testBundle-(.*)\\.xctestconfiguration"];}];
  id packageConfigArg = [OCMArg checkWithBlock:^BOOL(NSString *path){return [self.class isGoodConfigurationPath:path pattern:@"\\/appData\\.xcappdata\\/AppData\\/tmp\\/testBundle\\/testBundle-(.*)\\.xctestconfiguration"];}];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] writeData:[OCMArg any] toFile:packageConfigArg options:0 error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] writeData:[OCMArg any] toFile:localConfigArg options:0 error:[OCMArg anyObjectRef]];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] writeData:[OCMArg any] toFile:@"/appData.xcappdata/AppData/tmp/TestPlans/testBundle.xctest.xctestconfiguration" options:0 error:[OCMArg anyObjectRef]];//TODO
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] createDirectoryAtPath:@"/appData.xcappdata/AppData/tmp/TestPlans" withIntermediateDirectories:NO attributes:[OCMArg any] error:[OCMArg anyObjectRef]];

  OCMockObject<FBDeviceOperator> *deviceOperatorMock = [OCMockObject mockForProtocol:@protocol(FBDeviceOperator)];
  [[[deviceOperatorMock expect] andReturnValue:@YES] installApplicationWithPath:@"/app" error:[OCMArg anyObjectRef]];
  [[[deviceOperatorMock expect] andReturn:@"/remote/app"] applicationPathForApplicationWithBundleID:[OCMArg any] error:[OCMArg anyObjectRef]];
  [[[deviceOperatorMock expect] andReturn:@"/remote/data"] containerPathForApplicationWithBundleID:[OCMArg any] error:[OCMArg anyObjectRef]];
  [[[deviceOperatorMock expect] andReturnValue:@YES] uploadApplicationDataAtPath:@"/appData.xcappdata" bundleID:[OCMArg any] error:[OCMArg anyObjectRef]];

  FBDeviceTestPreparationStrategy *strategy =
  [FBDeviceTestPreparationStrategy strategyWithApplicationPath:@"/app"
                                           applicationDataPath:@"/appData.xcappdata"
                                                testBundlePath:@"/testBundle"
                                                   fileManager:fileManagerMock
   ];
  FBTestRunnerConfiguration *configuration = [strategy prepareTestWithDeviceOperator:deviceOperatorMock error:nil];

  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.testRunner);
  XCTAssertNotNil(configuration.launchArguments);
  XCTAssertNotNil(configuration.launchEnvironment);
  XCTAssertNotNil(configuration.launchEnvironment[@"XCTestConfigurationFilePath"]);
  XCTAssertEqualObjects(configuration.launchEnvironment[@"AppTargetLocation"], @"/remote/app/exec");
  XCTAssertEqualObjects(configuration.launchEnvironment[@"DYLD_FRAMEWORK_PATH"], @"/remote/data/tmp");
  XCTAssertEqualObjects(configuration.launchEnvironment[@"DYLD_LIBRARY_PATH"], @"/remote/data/tmp");
  XCTAssertEqualObjects(configuration.launchEnvironment[@"DYLD_INSERT_LIBRARIES"], @"/remote/data/tmp/IDEBundleInjection.framework/exec");
  XCTAssertEqualObjects(configuration.launchEnvironment[@"TestBundleLocation"], @"/testBundle");
  XCTAssertEqualObjects(configuration.launchEnvironment[@"XCInjectBundle"], @"/testBundle");
  XCTAssertEqualObjects(configuration.launchEnvironment[@"XCInjectBundleInto"], @"/remote/app/exec");
  XCTAssertEqualObjects(configuration.launchEnvironment[@"XCTestConfigurationFilePath"], @"/remote/data/tmp/TestPlans/testBundle.xctest.xctestconfiguration");

  [deviceOperatorMock verify];
}

@end
