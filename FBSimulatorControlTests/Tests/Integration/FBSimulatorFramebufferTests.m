/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorFramebufferTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorFramebufferTests

- (void)testRecordsVideoForSimulatorApp
{
  if (!MTLCreateSystemDefaultDevice()) {
    NSLog(@"Skipping running -[%@ %@] since Metal is not supported on this Hardware", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }
  FBSimulatorBootConfiguration *bootConfiguration = self.bootConfiguration;
  if (!FBXcodeConfiguration.isXcode8OrGreater) {
    NSLog(@"Skipping running -[%@ %@] since Xcode 8 or greater is required", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }

  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithConfiguration:self.simulatorConfiguration bootConfiguration:bootConfiguration];
  [self assertSimulator:simulator launches:self.safariAppLaunch];
  NSError *error = nil;
  id<FBVideoRecordingSession> session = [simulator startRecordingToFile:nil error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(session);
  [self assertSimulator:simulator launches:self.tableSearchAppLaunch];
  [session terminate];
}

@end
