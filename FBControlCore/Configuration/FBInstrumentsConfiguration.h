/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Value object with the information required to launch an instruments operation.
 */
@interface FBInstrumentsConfiguration : NSObject <NSCopying>

#pragma mark Initializers

/**
 Creates and returns a new Configuration with the provided parameters

 @param instrumentName the name of the instrument
 @return a new Configuration Object with the arguments applied.
 */
+ (instancetype)configurationWithInstrumentName:(NSString *)instrumentName targetApplication:(NSString *)targetApplication environment:(NSDictionary<NSString *, NSString *> *)environment arguments:(NSArray<NSString *> *)arguments duration:(NSTimeInterval)duration;

#pragma mark Properties

/**
 The Instrument Name
 */
@property (nonatomic, copy, readonly) NSString *instrumentName;

/**
 The target application bundle id.
 */
@property (nonatomic, copy, readonly) NSString *targetApplication;

/**
 The target application environment
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *environment;

/**
 The arguments to the target application.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;

/**
 The duration to run the instument for.
 */
@property (nonatomic, assign, readonly) NSTimeInterval duration;

@end

NS_ASSUME_NONNULL_END
