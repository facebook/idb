/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBProcessIO.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An abstract value object for launching both regular and applications processes.
 */
@interface FBProcessLaunchConfiguration <StdInType : id, StdOutType : id, StdErrType : id> : NSObject

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
@property (nonatomic, strong, readonly) FBProcessIO<StdInType, StdOutType, StdErrType> *io;

/**
 The Designated Initializer.

 @param arguments the Arguments.
 @param environment the Environment.
 @param io the IO object.
 @return a new FBProcessLaunchConfiguration Instance.
 */
- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment io:(FBProcessIO<StdInType, StdOutType, StdErrType> *)io;

@end

NS_ASSUME_NONNULL_END
