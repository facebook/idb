/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBProcessLaunchConfiguration.h>
#import <FBControlCore/FBJSONConversion.h>

@class FBApplicationBundle;
@class FBBinaryDescriptor;
@class FBProcessOutputConfiguration;

NS_ASSUME_NONNULL_BEGIN

/**
 A Value object with the information required to launch a Binary Agent.
 */
@interface FBAgentLaunchConfiguration : FBProcessLaunchConfiguration <FBJSONDeserializable>

/**
 Creates and returns a new Configuration with the provided parameters

 @param agentBinary the Binary Path of the agent to Launch. Must not be nil.
 @param arguments an array-of-strings of arguments to the process. Must not be nil.
 @param environment a Dictionary, mapping Strings to Strings of the Environment to set in the launched Application process. Must not be nil.
 @param output the output configuration for the launched process.
 @return a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithBinary:(FBBinaryDescriptor *)agentBinary arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(FBProcessOutputConfiguration *)output;

/**
 The Binary Path of the agent to Launch.
 */
@property (nonatomic, copy, readonly) FBBinaryDescriptor *agentBinary;

@end

NS_ASSUME_NONNULL_END
