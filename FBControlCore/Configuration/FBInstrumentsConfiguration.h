/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Contains all the timings for an instruments operation.
 */
@interface FBInstrumentsTimings : NSObject

#pragma mark Initializers

/**
 Creates and returns a new FBInstrumentsTimings object with the provided parameters

 @param terminateTimeout timeout for stopping Instruments
 @param launchRetryTimeout timeout for launching Instruments
 @param launchErrorTimeout timeout for the Instruments launch error message to pop up
 @param operationDuration the total duration for the Instruments operation
 @return a new FBInstrumentsTimings object with the specified timing values.
 */
+ (instancetype)timingsWithTerminateTimeout:(NSTimeInterval)terminateTimeout launchRetryTimeout:(NSTimeInterval)launchRetryTimeout launchErrorTimeout:(NSTimeInterval)launchErrorTimeout operationDuration:(NSTimeInterval)operationDuration;

/**
 The maximum backoff time when stopping Instruments.
 */
@property (nonatomic, readonly, assign) NSTimeInterval terminateTimeout;

/**
 The timeout waiting for Instruments to start properly.
 */
@property (nonatomic, readonly, assign) NSTimeInterval launchRetryTimeout;

/**
 The time waiting for the Instruments launch error message to appear.
 */
@property (nonatomic, readonly, assign) NSTimeInterval launchErrorTimeout;

/**
 The total operation duration for the Instruments operation.
 */
@property (nonatomic, readonly, assign) NSTimeInterval operationDuration;

@end

/**
 A Value object with the information required to launch an instruments operation.
 */
@interface FBInstrumentsConfiguration : NSObject <NSCopying>

#pragma mark Initializers

/**
 Creates and returns a new Configuration with the provided parameters

 @param templateName the name of the template
 @return a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithTemplateName:(NSString *)templateName targetApplication:(NSString *)targetApplication appEnvironment:(NSDictionary<NSString *, NSString *> *)appEnvironment appArguments:(NSArray<NSString *> *)appArguments toolArguments:(NSArray<NSString *> *)toolArguments timings:(FBInstrumentsTimings *)timings;

- (instancetype)initWithTemplateName:(NSString *)templateName targetApplication:(NSString *)targetApplication appEnvironment:(NSDictionary<NSString *, NSString *> *)appEnvironment appArguments:(NSArray<NSString *> *)appArguments toolArguments:(NSArray<NSString *> *)toolArguments timings:(FBInstrumentsTimings *)timings;

#pragma mark Properties

/**
 The template name or path.
 */
@property (nonatomic, readonly, copy) NSString *templateName;

/**
 The target application bundle id.
 */
@property (nonatomic, readonly, copy) NSString *targetApplication;

/**
 The target application environment.
 */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *appEnvironment;

/**
 The arguments to the target application.
 */
@property (nonatomic, readonly, copy) NSArray<NSString *> *appArguments;

/**
 Additional arguments.
 */
@property (nonatomic, readonly, copy) NSArray<NSString *> *toolArguments;

/**
 All the timings for the Instruments operation.
 */
@property (nonatomic, readonly, copy) FBInstrumentsTimings *timings;

@end

NS_ASSUME_NONNULL_END
