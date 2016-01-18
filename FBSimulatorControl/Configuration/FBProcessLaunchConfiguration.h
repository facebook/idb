/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulator;
@class FBSimulatorApplication;
@class FBSimulatorBinary;

/**
 An abstract value object for launching both agents and applications
 */
@interface FBProcessLaunchConfiguration : NSObject <NSCopying, NSCoding>

/**
 An NSArray<NSString *> of arguments to the process.
 */
@property (nonatomic, copy, readonly) NSArray *arguments;

/**
 A NSDictionary<NSString *, NSString *> of the Environment of the launched Application process.
 */
@property (nonatomic, copy, readonly) NSDictionary *environment;

/**
 The file path where the stdout of the launched process should be written.
 */
@property (nonatomic, copy, readonly) NSString *stdOutPath;

/**
 The file path where the stderr of the launched process should be written.
 */
@property (nonatomic, copy, readonly) NSString *stdErrPath;

/**
 A Full Description of the reciever.
 */
- (NSString *)debugDescription;

/**
 A Partial Description of the reciever.
 */
- (NSString *)shortDescription;

@end

/**
 A Value object with the information required to launch an Application.
 */
@interface FBApplicationLaunchConfiguration : FBProcessLaunchConfiguration

/**
 Creates and returns a new Configuration with the provided parameters

 @param application the Application to Launch.
 @param arguments an NSArray<NSString *> of arguments to the process.
 @param environment a NSDictionary<NSString *, NSString *> of the Environment of the launched Application process.
 @returns a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithApplication:(FBSimulatorApplication *)application arguments:(NSArray *)arguments environment:(NSDictionary *)environment;

/**
 Creates and returns a new Configuration with the provided parameters

 @param application the Application to Launch.
 @param arguments an NSArray<NSString *> of arguments to the process.
 @param environment a NSDictionary<NSString *, NSString *> of the Environment of the launched Application process.
 @param stdOutPath the file path where the stderr of the launched process should be written. May be nil.
 @param stdErrPath The file path where the stderr of the launched process should be written. May be nil.
 @returns a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithApplication:(FBSimulatorApplication *)application arguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath;

/**
 The Bundle ID of the the Application to Launch.
 */
@property (nonatomic, copy, readonly) NSString *bundleID;

@end

/**
 A Value object with the information required to launch a Binary Agent.
 */
@interface FBAgentLaunchConfiguration : FBProcessLaunchConfiguration

/**
 Creates and returns a new Configuration with the provided parameters

 @param agentBinary the Binary Path of the agent to Launch
 @param arguments an array-of-strings of arguments to the process
 @param environment a Dictionary, mapping Strings to Strings of the Environment to set in the launched Application process
 @returns a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithBinary:(FBSimulatorBinary *)agentBinary arguments:(NSArray *)arguments environment:(NSDictionary *)environment;

/**
 Creates and returns a new Configuration with the provided parameters

 @param agentBinary the Binary Path of the agent to Launch
 @param arguments an array-of-strings of arguments to the process
 @param environment a Dictionary, mapping Strings to Strings of the Environment to set in the launched Application process
 @param stdOutPath the file path where the stderr of the launched process should be written. May be nil.
 @param stdErrPath The file path where the stderr of the launched process should be written. May be nil.
 @returns a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithBinary:(FBSimulatorBinary *)agentBinary arguments:(NSArray *)arguments environment:(NSDictionary *)environment stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath;

/**
 The Binary Path of the agent to Launch.
 */
@property (nonatomic, copy, readonly) FBSimulatorBinary *agentBinary;

@end
