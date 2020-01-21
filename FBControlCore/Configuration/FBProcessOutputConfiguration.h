/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessOutput;

@protocol FBiOSTarget;

/**
 The Marker File Path if a File is to be output to a default location.
 */
extern NSString *const FBProcessOutputToFileDefaultLocation;

/**
 The Output Configuration for a Process.
 */
@interface FBProcessOutputConfiguration : NSObject <NSCopying, FBJSONSerializable, FBJSONDeserializable>

#pragma mark Initializers

/**
 The Designated Initializer

 @param stdOut the stdout, see the documentation for the stdOut property for details.
 @param stdErr the stderr, see the documentation for the stdErr property for details.
 @param error an error if the parameters are incorrect.
 @return a new configuration, or nil if the parameters are incorrect.
 */
+ (nullable instancetype)configurationWithStdOut:(id)stdOut stdErr:(id)stdErr error:(NSError **)error;

/**
 The Default Configuration, which outputs to the default location.
 */
+ (instancetype)defaultOutputToFile;

/**
 The Default Configuration, which does not redirect output.
 */
+ (instancetype)outputToDevNull;

/**
 Construct a copy of the receiver, with the stdOut applied

 @param stdOut the stdout, see the documentation for the stdOut property for details.
 @param error an error if the parameters are incorrect.
 @return a new configuration, or nil if the stdOut is incorrectly defined.
 */
- (nullable instancetype)withStdOut:(id)stdOut error:(NSError **)error;

/**
 Construct a copy of the receiver, with the stdErr applied

 @param stdErr the stdout, see the documentation for the stdOut property for details.
 @param error an error if the parameters are incorrect.
 @return a new configuration, or nil if the stdErr is incorrectly defined.
 */
- (nullable instancetype)withStdErr:(id)stdErr error:(NSError **)error;

#pragma mark Properties

/**
 The Output Configuration for stdout.
 Must be one of the following:
 - NSNull if the output is not to be redirected.
 - NSString for the File Path to output to.
 - FBProcessOutputToDefaultLocation if the output is to be directed to a file, at a default location.
 - FBDataConsumer for consuming the output.
 */
@property (nonatomic, strong, readonly) id stdOut;

/**
 The Output Configuration for stderr.
 Must be one of the following:
 - NSNull if the output is not to be redirected.
 - NSString for the File Path to output to.
 - FBProcessOutputToDefaultLocation if the output is to be directed to a file, at a default location.
 - FBDataConsumer for consuming the output.
 */
@property (nonatomic, strong, readonly) id stdErr;

#pragma mark Public Methods

/**
 Creates the IO wrapper object for a given target

 @param target the target to create the output for.
 @return a Future that wraps the IO.
 */
- (FBFuture<FBProcessIO *> *)createIOForTarget:(id<FBiOSTarget>)target;

@end

NS_ASSUME_NONNULL_END
