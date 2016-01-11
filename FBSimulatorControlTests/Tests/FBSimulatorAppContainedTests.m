/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import "FBSimulatorTestTemplates.h"
#import "FBSimulatorControlGlobalConfiguration.h"

@interface FBSimulatorAppContainedTests_DefaultSet : FBSimulatorTestTemplates

@end

@implementation FBSimulatorAppContainedTests_DefaultSet

- (NSString *)deviceSetPath
{
  return nil;
}

- (void)testLaunchesiPhone
{
  [self doTestLaunchesiPhone];
}

- (void)testLaunchesiPad
{
  [self doTestLaunchesiPad];
}

- (void)testLaunchesWatch
{
  [self doTestLaunchesWatch];
}

- (void)testLaunchesTV
{
  [self doTestLaunchesTV];
}

- (void)testLaunchesMultipleSimulators
{
  [self doTestLaunchesMultipleSimulators];
}

- (void)testLaunchesSafariApplication
{
  [self doTestLaunchesSafariApplication];
}

- (void)testRelaunchesSafariApplication
{
  [self doTestRelaunchesSafariApplication];
}

- (void)testLaunchesSampleApplication
{
  [self doTestLaunchesSafariApplication];
}

@end

@interface FBSimulatorAppContainedTests_CustomSet : FBSimulatorTestTemplates

@end

@implementation FBSimulatorAppContainedTests_CustomSet

- (NSString *)deviceSetPath
{
  return [NSTemporaryDirectory() stringByAppendingPathComponent:@"FBSimulatorControlSimulatorLaunchTests_CustomSet"];
}

- (void)testLaunchesiPhone
{
  if (!FBSimulatorControlGlobalConfiguration.supportsCustomDeviceSets) {
    NSLog(@"-[%@ %@] can't run as Custom Device Sets are not supported for this version of Xcode", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }
  [self doTestLaunchesiPhone];
}

- (void)testLaunchesiPad
{
  if (!FBSimulatorControlGlobalConfiguration.supportsCustomDeviceSets) {
    NSLog(@"-[%@ %@] can't run as Custom Device Sets are not supported for this version of Xcode", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }
  [self doTestLaunchesiPad];
}

- (void)testLaunchesWatch
{
  if (!FBSimulatorControlGlobalConfiguration.supportsCustomDeviceSets) {
    NSLog(@"-[%@ %@] can't run as Custom Device Sets are not supported for this version of Xcode", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }
  [self doTestLaunchesWatch];
}

- (void)testLaunchesTV
{
  if (!FBSimulatorControlGlobalConfiguration.supportsCustomDeviceSets) {
    NSLog(@"-[%@ %@] can't run as Custom Device Sets are not supported for this version of Xcode", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }
  [self doTestLaunchesTV];
}

- (void)testLaunchesMultipleSimulators
{
  if (!FBSimulatorControlGlobalConfiguration.supportsCustomDeviceSets) {
    NSLog(@"-[%@ %@] can't run as Custom Device Sets are not supported for this version of Xcode", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }
  [self doTestLaunchesMultipleSimulators];
}

- (void)testLaunchesSafariApplication
{
  if (!FBSimulatorControlGlobalConfiguration.supportsCustomDeviceSets) {
    NSLog(@"-[%@ %@] can't run as Custom Device Sets are not supported for this version of Xcode", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }
  [self doTestLaunchesSafariApplication];
}

- (void)testRelaunchesSafariApplication
{
  if (!FBSimulatorControlGlobalConfiguration.supportsCustomDeviceSets) {
    NSLog(@"-[%@ %@] can't run as Custom Device Sets are not supported for this version of Xcode", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }
  [self doTestRelaunchesSafariApplication];
}

- (void)testLaunchesSampleApplication
{
  if (!FBSimulatorControlGlobalConfiguration.supportsCustomDeviceSets) {
    NSLog(@"-[%@ %@] can't run as Custom Device Sets are not supported for this version of Xcode", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }
  [self doTestLaunchesSafariApplication];
}

@end
