/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBSimulatorControl/FBSimulator.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulatorApplicationOperation;
@class FBApplicationLaunchConfiguration;
@class FBProcessInfo;
@class FBSimulator;
@class FBSimulatorAgentOperation;
@class FBSimulatorConnection;
@class FBTestManager;
@protocol FBJSONSerializable;

/**
 A receiver of Simulator Events
 */
@protocol FBSimulatorEventSink <NSObject>

/**
 Event for the launch of a Simulator's Container Application Process.
 This is the Simulator.app's Process.

 @param applicationProcess the Process Information for the launched Application Process.
 */
- (void)containerApplicationDidLaunch:(FBProcessInfo *)applicationProcess;

/**
 Event for the launch of a Simulator's Container Application Process.
 This is the Simulator.app's Process.

 @param applicationProcess the Process Information for the terminated Application Process.
 @param expected whether the termination was expected or not.
 */
- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected;

/**
 Event for the Direct Launch of a Simulator Bridge.

 @param connection the Simulator Bridge of the Simulator.
 */
- (void)connectionDidConnect:(FBSimulatorConnection *)connection;

/**
 Event for the termination of a Simulator Framebuffer.

 @param connection the Simulator Bridge of the Simulator.
 @param expected whether the termination was expected or not.
 */
- (void)connectionDidDisconnect:(FBSimulatorConnection *)connection expected:(BOOL)expected;

/**
 Event for the launch of a Simulator's launchd_sim.

 @param launchdProcess the launchd_sim process
 */
- (void)simulatorDidLaunch:(FBProcessInfo *)launchdProcess;

/**
 Event for the termination of a Simulator's launchd_sim.

 @param launchdProcess the launchd_sim process
 */
- (void)simulatorDidTerminate:(FBProcessInfo *)launchdProcess expected:(BOOL)expected;

/**
 Event for the launch of an Agent.

 @param operation the Launched Agent Operation.
 */
- (void)agentDidLaunch:(FBSimulatorAgentOperation *)operation;

/**
 Event of the termination of an agent.

 @param operation the Terminated. Agent Operation.
 @param statLoc the termination status. Documented in waitpid(2).
 */
- (void)agentDidTerminate:(FBSimulatorAgentOperation *)operation statLoc:(int)statLoc;

/**
 Event for the launch of an Application.

 @param operation the Application Operation.
 */
- (void)applicationDidLaunch:(FBSimulatorApplicationOperation *)operation;

/**
 Event for the termination of an Application.

 @param operation the Application Operation.
 @param expected whether the termination was expected or not.
 */
- (void)applicationDidTerminate:(FBSimulatorApplicationOperation *)operation expected:(BOOL)expected;

/**
 Event for the change in a Simulator's state.

 @param state the changed state.
 */
- (void)didChangeState:(FBiOSTargetState)state;

@end

NS_ASSUME_NONNULL_END
