/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBAgentLaunchStrategy.h>

NS_ASSUME_NONNULL_BEGIN

@class FBApplicationLaunchConfiguration;
@class FBProcessInfo;

/**
 The Termination Handle Type for an Agent.
 */
extern FBTerminationHandleType const FBTerminationHandleTypeSimulatorAgent;

/**
 An Operation for an Agent.
 This class is explicitly a reference type as it retains the File Handles that are used by the Agent Process.
 The lifecycle of the process is managed internally and this class should not be instantiated directly by consumers.
 */
@interface FBSimulatorAgentOperation : NSObject <FBTerminationAwaitable>

/**
 The Configuration Launched with.
 */
@property (nonatomic, copy, readonly) FBAgentLaunchConfiguration *configuration;

/**
 The stdout File Handle.
 */
@property (nonatomic, strong, nullable, readonly) NSFileHandle *stdOutHandle;

/**
 The stderr File Handle.
 */
@property (nonatomic, strong, nullable, readonly) NSFileHandle *stdErrHandle;

/**
 The Launched Process Info.
 */
@property (nonatomic, copy, nullable, readonly) FBProcessInfo *process;

/**
 The Handler that to provide to the launch.
 */
@property (nonatomic, copy, nullable, readonly) FBAgentTerminationHandler handler;

@end

/**
 Private methods that should not be called by consumers.
 */
@interface FBSimulatorAgentOperation (Private)

/**
 The Designated Initializer.

 @param simulator the Simulator the Agent is launched in.
 @param configuration the configuration the process was launched with.
 @param stdOutHandle the File Handle of the Stdout.
 @param stdErrHandle the File Handle of the Stderr.
 @param handler the handler continuation.
 */
+ (instancetype)operationWithSimulator:(FBSimulator *)simulator configuration:(FBAgentLaunchConfiguration *)configuration stdOutHandle:(nullable NSFileHandle *)stdOutHandle stdErrHandle:(nullable NSFileHandle *)stdErrHandle handler:(nullable FBAgentTerminationHandler)handler;

/**
 Called internally by the framework when the owning process has been launched.
 This should never be called by consumers.

 @param process the process info of the launched process.
 */
- (void)processDidLaunch:(FBProcessInfo *)process;

@end

NS_ASSUME_NONNULL_END
