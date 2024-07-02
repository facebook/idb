/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBProcessStream.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A result of "attaching" to an IO object, realized as file descriptors.
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

/**
 Detach from all the streams.
 This may be called multiple times, the underlying streams will only detach once per instance.
 */
- (FBFuture<NSNull *> *)detach;

@end

/**
 A result of "attaching" to an IO object, realized as file paths.
 */
@interface FBProcessFileAttachment : NSObject

/**
 The attachment for stdout.
 */
@property (nonatomic, strong, nullable, readonly) id<FBProcessFileOutput> stdOut;

/**
 The attachment for stderr.
 */
@property (nonatomic, strong, nullable, readonly) id<FBProcessFileOutput> stdErr;

/**
 Detach from all the streams.
 This may be called multiple times, the underlying streams will only detach once per instance.
 */
- (FBFuture<NSNull *> *)detach;

@end

/**
 A composite of streams for the stdin, stdout and stderr streams connected to a process.
 */
@interface FBProcessIO <StdInType : id, StdOutType : id, StdErrType : id> : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param stdIn the stdin.
 @param stdOut the stdout.
 @param stdErr the stderr.
 @return a new FBProcessIO instance.
 */
- (instancetype)initWithStdIn:(nullable FBProcessInput<StdInType> *)stdIn stdOut:(nullable FBProcessOutput<StdOutType> *)stdOut stdErr:(nullable FBProcessOutput<StdErrType> *)stdErr;

/**
 An IO object that accepts no input and returns no output.
 */
+ (instancetype)outputToDevNull;

#pragma mark Properties

/**
 The FBProcessInput for stdin.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessInput<StdInType> *stdIn;

/**
The FBProcessOutput for stdout.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessOutput<StdOutType> *stdOut;

/**
 The FBProcessOutput for stderr.
 */
@property (nonatomic, strong, nullable, readonly) FBProcessOutput<StdErrType> *stdErr;

/**
 The queue to use.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

#pragma mark Methods

/**
 Attach to all the streams, returning the composite attachment for file descriptors.
 Will error if any of the stream attachments error.
 If any of the stream attachments error, then any succeeding attachments will detach.
 This should only be called once. Calling attach more than once per instance will fail.
 */
- (FBFuture<FBProcessIOAttachment *> *)attach;

/**
 Attach to all the streams, returning the composite attachment for file paths.
 Will error if any of the stream attachments error.
 If any of the stream attachments error, then any succeeding attachments will detach.
 */
- (FBFuture<FBProcessFileAttachment *> *)attachViaFile;

@end

NS_ASSUME_NONNULL_END
