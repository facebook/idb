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

@protocol FBSimulatorLogger;

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
+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration processQuery:(FBProcessQuery *)processQuery logger:(id<FBSimulatorLogger>)logger;

/**
 Kills the provided Simulators.
 This call ensures that all of the Simulators:
 1) Have any relevant Simulator.app process killed
 2) Have the appropriate SimDevice state at 'Shutdown'

 @param simulators the Simulators to Kill.
 @param error an error out if any error occured.
 @return an array of the Simulators that this were killed if successful, nil otherwise.
 */
- (NSArray *)killSimulators:(NSArray *)simulators withError:(NSError **)error;

/**
 'Shutting Down' a Simulator can be a little hairier than just calling 'shutdown'.
 This method of shutting down takes into account a variety of error states and attempts to recover from them.

 Note that 'Shutting Down' a Simulator is different to 'terminating' or 'killing'.
 Killing a Simulator will kill the Simulator.app process.
 When 'killing' a Simulator is expected that the process will termitate and some time later the state will update to 'Shutdown'.

 @param simulator the Simulator to safe shutdown.
 @param error a descriptive error for any error that occurred.
 @return YES if successful, NO otherwise.
 */
- (BOOL)safeShutdownSimulator:(FBSimulator *)simulator withError:(NSError **)error;

/**
 It's possible a Simulator is in a non-'Shutdown' state, without an associated Simulator process.
 These Simulators will be Shutdown to ensure that CoreSimulator is in a known-consistent state.

 @param simulators the Simulators to Kill.
 @param error an error out if any error occured.
 @returns an array of the Simulators that this were killed if successful, nil otherwise.
 */
- (NSArray *)ensureConsistencyForSimulators:(NSArray *)simulators withError:(NSError **)error;

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

/**
 Kills all of the 'com.apple.CoreSimulatorService' processes that are not used by the current `FBSimulatorControl` configuration.
 Running multiple versions of the Service on the same machine can lead to instability such as Simulator statuses not updating.

 @param error an error out if any error occured.
 @return an YES if successful, nil otherwise.
 */
- (BOOL)killSpuriousCoreSimulatorServicesWithError:(NSError **)error;

@end
