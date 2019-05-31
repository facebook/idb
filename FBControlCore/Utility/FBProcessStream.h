/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDataConsumer.h>
#import <FBControlCore/FBiOSTargetFuture.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An attached standard stream object.
 */
@interface FBProcessStreamAttachment : NSObject

/**
 The pipe to attach to, if backed by a pipe.
 Prefer using this over fileHandle if present.
 */
@property (nonatomic, readonly, strong, nullable) NSPipe *pipe;

/**
 The file handle to attach to.
 This will always be present.
 */
@property (nonatomic, readonly, strong) NSFileHandle *fileHandle;

@end

/**
 A Protocol that wraps the standard stream stdout, stderr, stdin
 */
@protocol FBStandardStream <NSObject>

/**
 Attaches to the output, returning an FBProcessStreamAttachment.

 @return A Future wrapping the FBProcessStreamAttachment.
 */
- (FBFuture<FBProcessStreamAttachment *> *)attach;

/**
 Tears down the output.

 @return A Future that resolves when teardown has completed.
 */
- (FBFuture<NSNull *> *)detach;

@end

/**
 Provides information about the state of a stream
 */
@protocol FBStandardStreamTransfer <NSObject>

/**
 The number of bytes transferred.
 */
@property (nonatomic, assign, readonly) ssize_t bytesTransferred;

@end

/**
 Process Output that can be provided through a file.
 */
@protocol FBProcessFileOutput <NSObject>

/**
 The File Path to write to.
 */
@property (nonatomic, copy, readonly) NSString *filePath;

/**
 Should be called just after the the file path has been written to.
 */
- (FBFuture<NSNull *> *)startReading;

/**
 Should be called just after the the file has stopped being written to.
 */
- (FBFuture<NSNull *> *)stopReading;

@end

/**
 Process Output that can be provided through a file.
 */
@protocol FBProcessOutput <NSObject>

/**
 Allows the reciever to be written to via a file instead of via a file handle.
 This is desirable to use when interacting with an API that doesn't support writing to a file handle.

 @return A Future wrapping a FBProcessFileOutput instance.
 */
- (FBFuture<id<FBProcessFileOutput>> *)providedThroughFile;

/**
 Allows the reciever to be written to via a Data Consumer.

 @return A Future wrapping a FBDataConsumer instance.
 */
- (FBFuture<id<FBDataConsumer>> *)providedThroughConsumer;

@end

/**
 The Termination Handle Type for Process Output.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeProcessOutput;

/**
 A container object for the output of a process.
 */
@interface FBProcessOutput<WrappedType> : NSObject <FBStandardStream, FBProcessOutput>

#pragma mark Initializers

/**
 An Output Container for /dev/nul

 @return a Process Output instance.
 */
+ (FBProcessOutput<NSNull *> *)outputForNullDevice;

/**
 An Output Container for a File Path.

 @param filePath the File Path to write to, may not be nil.
 @return a Process Output instance.
 */
+ (FBProcessOutput<NSString *> *)outputForFilePath:(NSString *)filePath;

/**
 An Output Container for an Input Stream

 @return a Process Output instance.
 */
+ (FBProcessOutput<NSInputStream *> *)outputToInputStream;

/**
 An Output Container that passes to Data Consumer.

 @param dataConsumer the file consumer to write to.
 @param logger the logger to log to.
 @return a Process Output instance.
 */
+ (FBProcessOutput<id<FBDataConsumer>> *)outputForDataConsumer:(id<FBDataConsumer>)dataConsumer logger:(nullable id<FBControlCoreLogger>)logger;

/**
 An Output Container that passes to Data Consumer.

 @param dataConsumer the data consumer to write to.
 @return a Process Output instance.
 */
+ (FBProcessOutput<id<FBDataConsumer>> *)outputForDataConsumer:(id<FBDataConsumer>)dataConsumer;

/**
 An Output Container that writes to a logger

 @param logger the logger to log to.
 @return a Process Output instance.
 */
+ (FBProcessOutput<id<FBControlCoreLogger>> *)outputForLogger:(id<FBControlCoreLogger>)logger;

/**
 An Output Container that accumilates data in memory

 @param data the mutable data to append to.
 @return a Process Output instance.
 */
+ (FBProcessOutput<NSMutableData *> *)outputToMutableData:(NSMutableData *)data;

/**
 An Output Container that accumilates data in memory, exposing it as a string.

 @param data the mutable data to append to.
 @return a Process Output instance.
 */
+ (FBProcessOutput<NSString *> *)outputToStringBackedByMutableData:(NSMutableData *)data;

#pragma mark Properties

/**
 The File Handle.
 */
@property (nonatomic, strong, readonly) WrappedType contents;

@end

/**
 A container object for the input of a process.
 */
@interface FBProcessInput<WrappedType> : NSObject <FBStandardStream>

#pragma mark Initializers

/**
 An input container that provides a data consumer.
 The 'contents' field will contain an opaque consumer that can be written to externally.

 @return a FBProcessInput instance wrapping a data consumer.
 */
+ (FBProcessInput<id<FBDataConsumer>> *)inputFromConsumer;

/**
 An input container that provides an NSOutputStream.
 The 'contents' field will contain an NSOutputStream that can be written to.

 @return a FBProcessInput instance wrapping an NSOutputStream.
 */
+ (FBProcessInput<NSOutputStream *> *)inputFromStream;

/**
 An Input container that connects data to the iput.

 @param data the data to send.
 @return a Process Input instance.
 */
+ (FBProcessInput<NSData *> *)inputFromData:(NSData *)data;

#pragma mark Properties

/**
 The File Handle.
 */
@property (nonatomic, strong, readonly) WrappedType contents;

@end

NS_ASSUME_NONNULL_END
