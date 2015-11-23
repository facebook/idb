/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorControlConfiguration;

/**
 Strategies for Terminating Simulators
 */
@interface FBSimulatorTerminationStrategy : NSObject

/**
 A Strategy that uses Pgrep/Pkill.
 */
+ (instancetype)usingKillOnConfiguration:(FBSimulatorControlConfiguration *)configuration allSimulators:(NSArray *)allSimulators;

/**
 Kills all of the Simulators the reciever's Device Set.

 @param error an error out if any error occured.
 @returns an array of the Simulators that this were killed if successful, nil otherwise.
 */
- (NSArray *)killAllWithError:(NSError **)error;

/**
 Kills the provided Simulators.

 @param simulators the Simulators to Kill.
 @param error an error out if any error occured.
 @returns an array of the Simulators that this were killed if successful, nil otherwise.
 */
- (NSArray *)killSimulators:(NSArray *)simulators withError:(NSError **)error;

/**
 Kills all of the Simulators that are not launched by `FBSimulatorControl`. These can be Simulators launched via Xcode or Instruments.

 @param error an error out if any error occured.
 @returns an YES if successful, nil otherwise.
 */
- (BOOL)killSpuriousSimulatorsWithError:(NSError **)error;


@end
