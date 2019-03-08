/**
 * Copyright (c) Facebook, Inc. and its affiliates.
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
 Reads a file in the background, forwarding to a consumer.
 */
@interface FBFileReader : NSObject

#pragma mark Initializers

/**
 Creates a file reader from a NSFileHandle.
 The file handle passed in will be retained by the reader until reading has finished.
 The semantics of the closing of the underlying file descriptor are handled by NSFileHandle.
 File descriptors can be automatically closed when they are deallocated by creating a NSFileHandle with `closeOnDealloc:`.

 @param fileHandle the file handle to read from. It will be closed when the reader stops.
 @param consumer the consumer to forward to.
 @param logger the logger to use.
 @return a file reader.
 */
+ (instancetype)readerWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Creates a File Reader of Dispatch Data from a File Handle.

 @param fileHandle the file handle to read from. It will be closed when the reader stops.
 @param consumer the consumer to forward to.
 @param logger the logger to use.
 @return a File Reader.
 */
+ (instancetype)dispatchDataReaderWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBDispatchDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Creates a file reader for a file at path.
 A file handle will be internally created, and closed when reading has finished.

 @param filePath the File Path to read from.
 @param consumer the consumer to forward to.
 @param logger the logger to use.
 @return a File Reader, that is available when the underlying file handle has been opened.
 */
+ (FBFuture<FBFileReader *> *)readerWithFilePath:(NSString *)filePath consumer:(id<FBDataConsumer>)consumer logger:(nullable id<FBControlCoreLogger>)logger;

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

 @return a Future that resolves when the consumption of the file has finished. The value of the future is a zero error code on success, or an non-zero code on some read error.
 */
- (FBFuture<NSNumber *> *)stopReading;

#pragma mark Properties

/**
 The current state of the file reader.
 */
@property (atomic, assign, readonly) FBFileReaderState state;

/**
 A Future that resolves when the the reading of the file handle has ended and and end-of-file has been sent to the consumer.
 The value of the future is a zero on success, or an non-zero code with the wrapped read error code.
 This will not cancel any in-flight reading and can instead be used to observe when reading has finished.
 Cancelling the future will cause reading to be cancelled.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *finishedReading;

@end

NS_ASSUME_NONNULL_END
