/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDataConsumer.h>
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
 Whether the implementor should close when it reaches the end of it's stream.
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

/**
 A Protocol that wraps the standard stream stdout, stderr, stdin
 */
@protocol FBStandardStream <NSObject>

/**
 Attaches to the output, returning an FBProcessStreamAttachment.

 @return A Future wrapping the FBProcessStreamAttachment.
 */
- (nonnull FBFuture<FBProcessStreamAttachment *> *)attach;

/**
 Tears down the output.

 @return A Future that resolves when teardown has completed.
 */
- (nonnull FBFuture<NSNull *> *)detach;

@end

/**
 Provides information about the state of a stream
 */
@protocol FBStandardStreamTransfer <NSObject>

/**
 The number of bytes transferred.
 */
@property (nonatomic, readonly, assign) ssize_t bytesTransferred;

/**
 An error, if any has occured in the streaming of data to the input.
 */
@property (nullable, nonatomic, readonly, strong) NSError *streamError;

@end

/**
 Process Output that can be provided through a file.
 */
@protocol FBProcessFileOutput <NSObject>

/**
 The File Path to write to.
 */
@property (nonnull, nonatomic, readonly, copy) NSString *filePath;

/**
 Should be called just after the the file path has been written to.
 */
- (nonnull FBFuture<NSNull *> *)startReading;

/**
 Should be called just after the the file has stopped being written to.
 */
- (nonnull FBFuture<NSNull *> *)stopReading;

@end

/**
 Process Output that can be provided through a file.
 */
@protocol FBProcessOutput <NSObject>

/**
 Allows the receiver to be written to via a file instead of via a file handle.
 This is desirable to use when interacting with an API that doesn't support writing to a file handle.

 @return A Future wrapping a FBProcessFileOutput instance.
 */
- (nonnull FBFuture<id<FBProcessFileOutput>> *)providedThroughFile;

/**
 Allows the receiver to be written to via a Data Consumer.

 @return A Future wrapping a FBDataConsumer instance.
 */
- (nonnull FBFuture<id<FBDataConsumer>> *)providedThroughConsumer;

@end

/**
 A container object for the output of a process.
 */
@interface FBProcessOutput <WrappedType> : NSObject <FBStandardStream, FBProcessOutput>

#pragma mark Initializers

/**
 An Output Container for /dev/nul

 @return a Process Output instance.
 */
+ (nonnull FBProcessOutput<NSNull *> *)outputForNullDevice;

/**
 An Output Container for a File Path.

 @param filePath the File Path to write to, may not be nil.
 @return a Process Output instance.
 */
+ (nonnull FBProcessOutput<NSString *> *)outputForFilePath:(nonnull NSString *)filePath;

/**
 An Output Container for an Input Stream

 @return a Process Output instance.
 */
+ (nonnull FBProcessOutput<NSInputStream *> *)outputToInputStream;

/**
 An Output Container that passes to both a data consumer and a logger.

 @param dataConsumer the file consumer to write to.
 @param logger the logger to log to.
 @return a Process Output instance.
 */
+ (nonnull FBProcessOutput<id<FBDataConsumer>> *)outputForDataConsumer:(nonnull id<FBDataConsumer>)dataConsumer logger:(nonnull id<FBControlCoreLogger>)logger;

/**
 An Output Container that passes to Data Consumer.

 @param dataConsumer the data consumer to write to.
 @return a Process Output instance.
 */
+ (nonnull FBProcessOutput<id<FBDataConsumer>> *)outputForDataConsumer:(nonnull id<FBDataConsumer>)dataConsumer;

/**
 An Output Container that writes to a logger

 @param logger the logger to log to.
 @return a Process Output instance.
 */
+ (nonnull FBProcessOutput<id<FBControlCoreLogger>> *)outputForLogger:(nonnull id<FBControlCoreLogger>)logger;

/**
 An Output Container that accumilates data in memory

 @param data the mutable data to append to.
 @return a Process Output instance.
 */
+ (nonnull FBProcessOutput<NSMutableData *> *)outputToMutableData:(nonnull NSMutableData *)data;

/**
 An Output Container that accumilates data in memory, exposing it as a string.

 @param data the mutable data to append to.
 @return a Process Output instance.
 */
+ (nonnull FBProcessOutput<NSString *> *)outputToStringBackedByMutableData:(nonnull NSMutableData *)data;

#pragma mark Properties

/**
 The wrapped contents of the stream.
 */
@property (nonnull, nonatomic, readonly, strong) WrappedType contents;

@end

/**
 A container object for the input of a process.
 */
@interface FBProcessInput <WrappedType> : NSObject <FBStandardStream>

#pragma mark Initializers

/**
 An input container that provides a data consumer.
 The 'contents' field will contain an opaque consumer that can be written to externally.

 @return a FBProcessInput instance wrapping a data consumer.
 */
+ (nonnull FBProcessInput<id<FBDataConsumer>> *)inputFromConsumer;

/**
 An input container that provides an NSOutputStream.
 The 'contents' field will contain an NSOutputStream that can be written to.

 @return a FBProcessInput instance wrapping an NSOutputStream.
 */
+ (nonnull FBProcessInput<NSOutputStream *> *)inputFromStream;

/**
 An Input container that connects data to the iput.

 @param data the data to send.
 @return a Process Input instance.
 */
+ (nonnull FBProcessInput<NSData *> *)inputFromData:(nonnull NSData *)data;

#pragma mark Properties

/**
 The wrapped contents of the stream.
 */
@property (nonnull, nonatomic, readonly, strong) WrappedType contents;

@end
