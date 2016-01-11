/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import "FBSimulatorControlTestCase.h"

/**
 A Test Case that can be overriden to provide variations in configuration
 */
@interface FBSimulatorTestTemplates : FBSimulatorControlTestCase

- (NSArray *)expectedBootNotificationNames;

- (NSArray *)expectedShutdownNotificationNames;

- (void)doTestLaunchesSafariApplication;

- (void)doTestRelaunchesSafariApplication;

- (void)doTestLaunchesSampleApplication;

- (void)doTestLaunchesSingleSimulator:(FBSimulatorConfiguration *)configuration;

- (void)doTestLaunchesiPhone;

- (void)doTestLaunchesiPad;

- (void)doTestLaunchesWatch;

- (void)doTestLaunchesTV;

- (void)doTestLaunchesMultipleSimulators;

@end
