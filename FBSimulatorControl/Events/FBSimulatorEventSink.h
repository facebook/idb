/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulator.h>

@class FBAgentLaunchConfiguration;
@class FBApplicationLaunchConfiguration;
@class FBSimulator;
@class FBSimulatorApplication;
@class FBSimulatorLaunchInfo;
@protocol FBTerminationHandle;
@class FBProcessInfo;

/**
 A reciever of Simulator Events
 */
@protocol FBSimulatorEventSink <NSObject>

/**
 Event for the launch of a Simulator.
 */
- (void)didStartWithLaunchInfo:(FBSimulatorLaunchInfo *)launchInfo;

/**
 Event for the termination of a Simulator.

 @param expected whether the termination was expected or not.
 */
- (void)didTerminate:(BOOL)expected;

/**
 Event for the launch of an Agent.

 @param launchConfig the Agent Launch Configuration that was used to launch the Agentagent.
 @param agentProcess the resulting Process Info from the launch.
 @param stdOut the stdout file handle of the launched agent, may be nil.
 @param stdErr the stderr file handle of the launched agent, may be nil.
 */
- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr;

/**
 Event of the termination of an agent.

 @param agentProcess the process that was terminated.
 @param expected whether the termination was expected or not.
 */
- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected;

/**
 Event for the launch of an Application.

 @param launchConfig the Application Launch Configuration that was used to launch the Application.
 @param applicationProcess the resulting Process Info from the launch.
 @param stdOut the stdout file handle of the launched agent, may be nil.
 @param stdErr the stderr file handle of the launched agent, may be nil.
 */
- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr;

/**
 Event for the termination of an Application.

 @param applicationProcess the process that was terminated.
 @param expected whether the termination was expected or not.
 */
- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected;

/**
 Event for the the availablility of diagnostic information.
 Diagnostics can be keyed per-simulator or per-simulator-process.

 @param name the name of the diagnostic, must not be nil.
 @param process the process to key the diagnostic information for. If nil this is a simulator diagnostic.
 @param value the value of the diagnostic.
 */
- (void)diagnosticInformationAvailable:(NSString *)name process:(FBProcessInfo *)process value:(id<NSCopying, NSCoding>)value;

/**
 Event for the change in a Simulator's state.

 @param state the changed state.
 */
- (void)didChangeState:(FBSimulatorState)state;

/**
 Event for the availibility of new Termination Handle.

 @param terminationHandle the Termination Handle that is required to be called on Simulator teardown.
 */
- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle;

@end
