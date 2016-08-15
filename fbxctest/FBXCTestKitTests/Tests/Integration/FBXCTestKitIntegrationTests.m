// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBXCTestKitFixtures.h"
#import <FBXCTEstKit/FBXCTestKit.h>
#import <XCTest/XCTest.h>

@interface FBXCTestKitIntegrationTests : XCTestCase

@end

@implementation FBXCTestKitIntegrationTests

- (void)testRunTestsWithAppTest
{
  NSError *error;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures tableSearchApplicationPath];
  NSString *testBundlePath = [FBXCTestKitFixtures simpleTestTargetPath];
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@", testBundlePath, applicationPath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 5,OS=iOS 9.3", @"-appTest", appTestArgument ];

  FBTestRunConfiguration *configuration = [FBTestRunConfiguration new];
  [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);

  FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
  [testRunner executeTestsWithError:&error];
  XCTAssertNil(error);
}

@end
