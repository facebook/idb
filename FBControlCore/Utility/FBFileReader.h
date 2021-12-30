/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDataConsumer.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The File Reader States
 */
typedef NS_ENUM(NSUInteger, FBFileReaderState) {
  FBFileReaderStateNotStarted = 0,
  FBFileReaderStateReading = 1,
  FBFileReaderStateFinishedReadingNormally = 2,
  FBFileReaderStateFinishedReadingInError = 3,
  FBFileReaderStateFinishedReadingByCancellation = ECANCELED,
};

/**
 A Protocol for defining file reading.
 */
@protocol FBFileReader

#pragma mark Public Methods

/**
 Starts the reading the file.
 If this is called twice, then the future will resolve in error.

 @return a Future that resolves when the channel is setup.
 */
- (FBFuture<NSNull *> *)startReading;

/**
 Stops reading the file.
 The returned future returns when the end-of-file has been sent to the consumer.
 If the file reading has finished already, then the future will resolve instantly as there is no work to stop.
 Calling this is not mandatory. It's permissible to use the `finishedReading` future to observe when the reading ends naturally.
 At the point that the future is resolved, the file descriptor is no longer in use internally, so the caller may do as it pleases with the file descriptor that this reader wraps.

 @return a Future that resolves when the consumption of the file has finished. The value of the future is a zero error code on success, or an non-zero code on some read error.
 */
- (FBFuture<NSNumber *> *)stopReading;

/**
 Waits for the reader to finish reading, backing off to a forcing of stopping reading in the event of a timeout.
 At the point that the future is resolved, the file descriptor is no longer in use internally, so the caller may do as it pleases with the file descriptor that this reader wraps.

 @param timeout the timeout to wait before calling `stopReading`
 */
- (FBFuture<NSNumber *> *)finishedReadingWithTimeout:(NSTimeInterval)timeout;

#pragma mark Properties

/**
 The current state of the file reader.
 */
@property (atomic, assign, readonly) FBFileReaderState state;

/**
 A Future that resolves when the the reading of the file handle and has no pending operations on the file descriptor.
 By this point an end-of-file will also have been sent to the consumer.
 The value of the future is a zero on success, or an non-zero code with the wrapped read error code.
 This will not cancel any in-flight reading and can instead be used to observe when reading has finished.
 Cancelling the future will cause reading to be cancelled.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *finishedReading;

@end

/**
 Reads a file in the background, forwarding to a consumer.
 Closing of a file descriptor when reading has finished is also provided, where relevant.
 */
@interface FBFileReader : NSObject <FBFileReader>

#pragma mark Initializers

/**
 Creates a reader of NSData from a file descriptor.

 @param fileDescriptor the file descriptor to write to.
 @param closeOnEndOfFile YES if the file descriptor should be closed on consumeEndOfFile, NO otherwise.
 @param consumer the consumer to forward to.
 @param logger the logger to use.
 @return a file reader.
 */
+ (instancetype)readerWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile consumer:(id<FBDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Creates a reader of dispatch data from a file descriptor.

 @param fileDescriptor the file descriptor to write to.
 @param closeOnEndOfFile YES if the file descriptor should be closed on consumeEndOfFile, NO otherwise.
 @param consumer the consumer to forward to.
 @param logger the logger to use.
 @return a File Reader.
 */
+ (instancetype)dispatchDataReaderWithFileDescriptor:(int)fileDescriptor closeOnEndOfFile:(BOOL)closeOnEndOfFile consumer:(id<FBDispatchDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Creates a reader of NSData from a file at a path on the filesystem.
 A file handle will be internally created, and closed when reading has finished.

 @param filePath the file path to read from.
 @param consumer the consumer to forward to.
 @param logger the logger to use.
 @return a File Reader, that is available when the underlying file handle has been opened.
 */
+ (FBFuture<FBFileReader *> *)readerWithFilePath:(NSString *)filePath consumer:(id<FBDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
