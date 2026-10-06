/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/DataConsumer.h>
#import <FBControlCore/FBFuture.h>

typedef NS_ENUM(NSUInteger, FBProcessStreamAttachmentMode) {
  FBProcessStreamAttachmentModeInput = 0,
  FBProcessStreamAttachmentModeOutput = 1,
};

/**
 An attached standard stream object.
 */
@interface FBProcessStreamAttachment : NSObject

/**
 The file descriptor to attach to.
 */
@property (nonatomic, readonly, assign) int fileDescriptor;

/**
 Whether the implementor should close when it reaches the end of its stream.
 */
@property (nonatomic, readonly, assign) BOOL closeOnEndOfFile;

/**
 Whether the attachment represents an input or an output.
 */
@property (nonatomic, readonly, assign) FBProcessStreamAttachmentMode mode;

/**
 Checks fileDescriptor status and closes it if necessary;
 */
- (void)close;

@end

@protocol StandardStream;
@protocol StandardStreamTransfer;

/**
 A container object for the input of a process.
 */
@interface FBProcessInput <WrappedType> : NSObject

#pragma mark Initializers

/**
 An input container that provides a data consumer.
 The 'contents' field will contain an opaque consumer that can be written to externally.

 @return a FBProcessInput instance wrapping a data consumer.
 */
+ (nonnull FBProcessInput<id<DataConsumer>> *)inputFromConsumer;

/**
 An input container that provides an NSOutputStream.
 The 'contents' field will contain an NSOutputStream that can be written to.

 @return a FBProcessInput instance wrapping an NSOutputStream.
 */
+ (nonnull FBProcessInput<NSOutputStream *> *)inputFromStream;

/**
 An Input container that connects data to the input.

 @param data the data to send.
 @return a Process Input instance.
 */
+ (nonnull FBProcessInput<NSData *> *)inputFromData:(nonnull NSData *)data;

#pragma mark Properties

/**
 The wrapped contents of the stream.
 */
@property (nonnull, nonatomic, readonly, strong) WrappedType contents;

- (nonnull FBFuture<FBProcessStreamAttachment *> *)attach;
- (nonnull FBFuture<NSNull *> *)detach;

@end
