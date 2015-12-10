/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlTestCase.h"
#import "FBSimulatorControlFixtures.h"

@interface FBSimulatorVideoRecorderTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorVideoRecorderTests

- (void)disabled_testRecordsVideo
{
  FBSimulatorSession *session = [self createBootedSession];
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;

  [self.assert interactionSuccessful:[session.interact launchApplication:appLaunch]];

  FBSimulatorVideoRecorder *recorder = [FBSimulatorVideoRecorder forSimulator:session.simulator logger:nil];

  NSError *error = nil;
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
  FBApplicationLaunchConfiguration *appLaunch = self.safariAppLaunch;

  FBSimulatorSession *firstSession = [self createSession];
  [self.assert interactionSuccessful:[firstSession.interact.bootSimulator.tileSimulator.recordVideo launchApplication:appLaunch]];

  FBSimulatorSession *secondSession = [self createSession];
  [self.assert interactionSuccessful:[secondSession.interact.bootSimulator.tileSimulator.recordVideo launchApplication:appLaunch]];

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
