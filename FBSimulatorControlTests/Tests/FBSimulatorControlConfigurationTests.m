/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>

@interface FBSimulatorControlConfigurationTests : XCTestCase

@end

@implementation FBSimulatorControlConfigurationTests

- (void)testEqualityOfCopy
{
  FBSimulatorApplication *application = [FBSimulatorApplication simulatorApplicationWithError:nil];

  FBSimulatorControlConfiguration *config = [FBSimulatorControlConfiguration
    configurationWithSimulatorApplication:application
    deviceSetPath:nil
    namePrefix:@"TestEnv"
    bucket:1
    options:FBSimulatorManagementOptionsDeleteManagedSimulatorsOnFirstStart];
  FBSimulatorControlConfiguration *configCopy = [config copy];

  XCTAssertEqualObjects(config.simulatorApplication, configCopy.simulatorApplication);
  XCTAssertEqualObjects(config.namePrefix, configCopy.namePrefix);
  XCTAssertEqual(config.bucketID, configCopy.bucketID);
  XCTAssertEqual(config.options, configCopy.options);
  XCTAssertEqualObjects(config, configCopy);
}

@end
