/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBProcessStream.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A composite of all attachments.
 */
@interface FBProcessIOAttachment : NSObject

#pragma mark Properties

/**
 The attachment for stdin.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessStreamAttachment *stdIn;

/**
 The attachment for stdout.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessStreamAttachment *stdOut;

/**
 The attachment for stderr.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessStreamAttachment *stdErr;

@end

/**
 A composite of FBProcessStream.
 */
@interface FBProcessIO : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param stdIn the stdin.
 @param stdOut the stdout.
 @param stdErr the stderr.
 @return a new FBProcessIO instance.
 */
- (instancetype)initWithStdIn:(nullable FBProcessInput *)stdIn stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr;

#pragma mark Properties

/**
 The FBProcessInput for stdin.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessInput *stdIn;

/**
The FBProcessOutput for stdout.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessOutput *stdOut;

/**
 The FBProcessOutput for stderr.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessOutput *stdErr;

/**
 The queue to use.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

#pragma mark Methods

/**
 Attach to all the streams, returning the composite attachment.
 Will error if any of the stream attachments error.
 If any of the stream attachments error, then any succeeding attachments will detach.
 */
- (FBFuture<FBProcessIOAttachment *> *)attach;

/**
 Detach from all the streams.
 */
- (FBFuture<NSNull *> *)detach;

@end

NS_ASSUME_NONNULL_END
