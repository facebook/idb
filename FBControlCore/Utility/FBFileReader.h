/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDataConsumer.h>
#import <FBControlCore/FBFuture.h>

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
@protocol FBFileReaderProtocol

#pragma mark Public Methods

/**
 Starts the reading the file.
 If this is called twice, then the future will resolve in error.

 @return a Future that resolves when the channel is setup.
 */
- (nonnull FBFuture<NSNull *> *)startReading;

/**
 Stops reading the file.
 The returned future returns when the end-of-file has been sent to the consumer.
 If the file reading has finished already, then the future will resolve instantly as there is no work to stop.
 Calling this is not mandatory. It's permissible to use the `finishedReading` future to observe when the reading ends naturally.
 At the point that the future is resolved, the file descriptor is no longer in use internally, so the caller may do as it pleases with the file descriptor that this reader wraps.

 @return a Future that resolves when the consumption of the file has finished. The value of the future is a zero error code on success, or an non-zero code on some read error.
 */
- (nonnull FBFuture<NSNumber *> *)stopReading;

/**
 Waits for the reader to finish reading, backing off to a forcing of stopping reading in the event of a timeout.
 At the point that the future is resolved, the file descriptor is no longer in use internally, so the caller may do as it pleases with the file descriptor that this reader wraps.

 @param timeout the timeout to wait before calling `stopReading`
 */
- (nonnull FBFuture<NSNumber *> *)finishedReadingWithTimeout:(NSTimeInterval)timeout;

#pragma mark Properties

/**
 The current state of the file reader.
 */
@property (atomic, readonly, assign) FBFileReaderState state;

/**
 A Future that resolves when the the reading of the file handle and has no pending operations on the file descriptor.
 By this point an end-of-file will also have been sent to the consumer.
 The value of the future is a zero on success, or an non-zero code with the wrapped read error code.
 This will not cancel any in-flight reading and can instead be used to observe when reading has finished.
 Cancelling the future will cause reading to be cancelled.
 */
@property (nonnull, nonatomic, readonly, strong) FBFuture<NSNumber *> *finishedReading;

@end

// FBFileReader is now implemented in Swift.
