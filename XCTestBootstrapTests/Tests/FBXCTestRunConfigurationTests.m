//
//  FBXCTestRunConfigurationTests.m
//  FBSimulatorControl
//
//  Created by Plunien, Johannes(AWF) on 22/11/16.
//  Copyright © 2016 Facebook. All rights reserved.
//

#import <XCTest/XCTest.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestBootstrapFixtures.h"

@interface FBXCTestRunConfigurationTests : XCTestCase

@end

@implementation FBXCTestRunConfigurationTests

- (void)setUp
{
  [super setUp];

  NSError *error;
  [XCTestBootstrapFrameworkLoader loadPrivateFrameworks:nil error:&error];
  XCTAssertNil(error);
}

- (void)testReadingTestRunConfigurationAtPath
{
  NSError *error;
  FBXCTestRunConfiguration *testRunConfiguration = [[FBXCTestRunConfiguration
    withTestRunConfigurationAtPath:[FBXCTestRunConfigurationTests tableSearchXCTestRunPath]]
    buildWithError:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(testRunConfiguration.testHostPath);
  XCTAssertNotNil(testRunConfiguration.testBundlePath);
  XCTAssertEqualObjects(testRunConfiguration.arguments, (@[@"ARG1", @"ARG2", @"ARG3"]));
  XCTAssertEqualObjects(testRunConfiguration.environment[@"FOO"], @"BAR");
  XCTAssertEqualObjects(testRunConfiguration.environment[@"BLA"], @"FASEL");
  XCTAssertEqualObjects(testRunConfiguration.testsToSkip, [NSSet setWithObject:@"TableSearchTests/testSkipMe"]);
  XCTAssertEqualObjects(testRunConfiguration.testsToRun, [NSSet set]);
}

@end
