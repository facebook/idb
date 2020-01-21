/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBDebugDescribeable.h>

NS_ASSUME_NONNULL_BEGIN

@class FBBinaryDescriptor;
@class FBProcessOutputConfiguration;

/**
 An abstract value object for launching both agents and applications
 */
@interface FBProcessLaunchConfiguration : NSObject <NSCopying, FBJSONSerializable, FBDebugDescribeable>

/**
 An NSArray<NSString *> of arguments to the process. Will not be nil.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;

/**
 A NSDictionary<NSString *, NSString *> of the Environment of the launched Application process. Will not be nil.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *environment;

/**
 The Process Output Configuration.
 */
@property (nonatomic, copy, readonly) FBProcessOutputConfiguration *output;

/**
 Creates a copy of the receiver, with the environment applied.

 @param environment the environment to use.
 @return a copy of the receiver, with the environment applied.
 */
- (instancetype)withEnvironment:(NSDictionary<NSString *, NSString *> *)environment;

/**
 Creates a copy of the receiver, with the arguments applied.

 @param arguments the arguments to use.
 @return a copy of the receiver, with the arguments applied.
 */
- (instancetype)withArguments:(NSArray<NSString *> *)arguments;

/**
 The Designated Initializer.

 @param arguments the Arguments.
 @param environment the Environment.
 @param output the Output Configuration.
 @return a new FBProcessLaunchConfiguration Instance.
 */
- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment output:(FBProcessOutputConfiguration *)output;

/**
 Extracts Common Values from JSON.

 @param json the JSON to extract from.
 @param argumentsOut an outparam for the Arguments.
 @param environmentOut an outparam for the Environment.
 @param outputOut an outparam for the Process Output.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
+ (BOOL)fromJSON:(id)json extractArguments:(NSArray<NSString *> *_Nullable*_Nullable)argumentsOut environment:(NSDictionary<NSString *, NSString *> *_Nullable*_Nullable)environmentOut output:(FBProcessOutputConfiguration *_Nullable*_Nullable)outputOut error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
