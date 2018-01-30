// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFileConsumer.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Reads a file in the background, forwarding to a consumer.
 */
@interface FBFileReader : NSObject

#pragma mark Initializers

/**
 Creates a File Reader from a File Handle.

 @param fileHandle the file handle to read from. It will be closed when the reader stops.
 @param consumer the consumer to forward to.
 @return a File Reader.
 */
+ (instancetype)readerWithFileHandle:(NSFileHandle *)fileHandle consumer:(id<FBFileConsumer>)consumer;

/**
 Creates a File Reader for a File at Path.

 @param filePath the File Path to read from.
 @param consumer the consumer to forward to.
 @return a File Reader, that is available when the underlying file handle has been opened.
 */
+ (FBFuture<FBFileReader *> *)readerWithFilePath:(NSString *)filePath consumer:(id<FBFileConsumer>)consumer;

#pragma mark Public Methods

/**
 Starts the Consumption of the File.

 @return a Future that resolves when the channel is setup.
 */
- (FBFuture<NSNull *> *)startReading;

/**
 Stops Reading the file.

 @return a Future that resolves when the consumption of the file has finished.
 */
- (FBFuture<NSNull *> *)stopReading;

/**
 A future that resolves when the reading has stopped.

 @return a Future that resolves when the consumption of the file has finished.
 */
- (FBFuture<NSNull *> *)completed;

@end

NS_ASSUME_NONNULL_END
