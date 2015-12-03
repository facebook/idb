/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorSession.h>

@class FBAgentLaunchConfiguration;
@class FBApplicationLaunchConfiguration;

/**
 Conveniences for starting managing the Session Lifecycle.
 */
@interface FBSimulatorSession (Convenience)

/**
 Re-launches the last terminated application.
 */
- (BOOL)relaunchAppWithError:(NSError **)error;

/**
 Terminates the last launched application.
 */
- (BOOL)terminateAppWithError:(NSError **)error;

@end
