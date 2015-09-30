/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBSimulatorControl/FBSimulatorControl+Private.h>
#import <FBSimulatorControl/FBSimulatorPool.h>
#import <FBSimulatorControl/FBSimulatorPool+Private.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulatorSession.h>
#import <FBSimulatorControl/FBSimulatorSessionInteraction.h>
#import <FBSimulatorControl/FBSimulatorSessionState.h>
#import <FBSimulatorControl/FBProcessLaunchConfiguration.h>
#import <FBSimulatorControl/FBSimulatorConfiguration.h>
#import <FBSimulatorControl/FBSimulatorVideoRecorder.h>
#import <FBSimulatorControl/NSRunLoop+SimulatorControlAdditions.h>

#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorVideoRecorderTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorVideoRecorderTests

- (void)disabled_testRecordsVideo
{
  NSError *error = nil;
  FBSimulatorSession *session = [self.control createSessionForSimulatorConfiguration:FBSimulatorConfiguration.iPhone5 error:&error];
  XCTAssertNotNil(session);
  XCTAssertNil(error);

  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithApplication:[FBSimulatorApplication systemApplicationNamed:@"MobileSafari"]
    arguments:@[]
    environment:@{}];

  XCTAssertTrue([[[session.interact
    bootSimulator]
    launchApplication:appLaunch]
    performInteractionWithError:&error]
  );

  FBSimulatorVideoRecorder *recorder = [FBSimulatorVideoRecorder forSimulator:session.simulator logger:nil];
  NSString *filePath = [[NSTemporaryDirectory() stringByAppendingString:NSUUID.UUID.UUIDString] stringByAppendingPathComponent:@"mp4"];
  XCTAssertTrue([recorder startRecordingToFilePath:filePath error:&error]);
  XCTAssertNil(error);

  // Spin the run loop a bit.
  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:10 untilTrue:^ BOOL {
    return NO;
  }];

  filePath = [recorder stopRecordingWithError:&error];
  XCTAssertNotNil(filePath);
  XCTAssertNil(error);
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:filePath]);
}

- (void)disabled_testMultipleTiledSimulators
{
  // Approval is required externally to the Test Runner. Without approval, the tests can't run
  if (!AXIsProcessTrusted()) {
    NSLog(@"%@ can't run as the host process isn't trusted", NSStringFromSelector(_cmd));
    return;
  }

  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
   configurationWithApplication:[FBSimulatorApplication systemApplicationNamed:@"MobileSafari"]
   arguments:@[]
   environment:@{}];

  NSError *error = nil;
  FBSimulatorSession *firstSession = [self.control createSessionForSimulatorConfiguration:FBSimulatorConfiguration.iPhone5 error:&error];
  XCTAssertNotNil(firstSession);
  XCTAssertNil(error);
  XCTAssertTrue([[[[[firstSession.interact
    bootSimulator]
    tileSimulator]
    recordVideo]
    launchApplication:appLaunch]
    performInteractionWithError:&error]
  );
  XCTAssertNil(error);

  FBSimulatorSession *secondSession = [self.control createSessionForSimulatorConfiguration:FBSimulatorConfiguration.iPhone5 error:&error];
  XCTAssertNotNil(secondSession);
  XCTAssertNil(error);
  XCTAssertTrue([[[[[secondSession.interact
    bootSimulator]
    tileSimulator]
    recordVideo]
    launchApplication:appLaunch]
    performInteractionWithError:&error]
  );
  XCTAssertNil(error);

  // Spin the run loop a bit.
  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:10 untilTrue:^ BOOL {
    return NO;
  }];

  NSString *filePath = firstSession.state.diagnostics[@"video"];
  XCTAssertNotNil(filePath);
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:filePath]);
  filePath = secondSession.state.diagnostics[@"video"];
  XCTAssertNotNil(filePath);
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:filePath]);
}

@end
