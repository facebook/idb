/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBProcessQuery;
@class FBSimulator;
@class FBSimulatorControlConfiguration;

@protocol FBControlCoreLogger;

/**
 A class for terminating Simulators.
 */
@interface FBSimulatorTerminationStrategy : NSObject

/**
 Creates a FBSimulatorTerminationStrategy using the provided configuration.

 @param configuration the Configuration of FBSimulatorControl.
 @param processQuery the process query object to use. If nil, one will be created
 @param logger the Logger to log all activities on.
 @return a configured FBSimulatorTerminationStrategy instance.
 */
+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration processQuery:(FBProcessQuery *)processQuery logger:(id<FBControlCoreLogger>)logger;

/**
 Kills the provided Simulators.
 This call ensures that all of the Simulators:
 1) Have any relevant Simulator.app process killed (if any applicable Simulator.app process is found).
 2) Have the appropriate SimDevice state at 'Shutdown'

 @param simulators the Simulators to Kill.
 @param error an error out if any error occured.
 @return an array of the Simulators that this were killed if successful, nil otherwise.
 */
- (NSArray *)killSimulators:(NSArray *)simulators withError:(NSError **)error;

/**
 Kills all of the Simulators that are not launched by `FBSimulatorControl`.
 This can mean Simulators that werelaunched via Xcode or Instruments.
 Getting a Simulator host into a clean state improves the general reliability of Simulator management and launching.
 In addition, performance should increase as these Simulators won't take up any system resources.

 To make the runtime environment more predicatable, it is best to avoid using FBSimulatorControl in conjuction with tradition Simulator launching systems at the same time.
 This method will not kill Simulators that are launched by FBSimulatorControl in another, or the same process.

 @param error an error out if any error occured.
 @return an YES if successful, nil otherwise.
 */
- (BOOL)killSpuriousSimulatorsWithError:(NSError **)error;

@end
