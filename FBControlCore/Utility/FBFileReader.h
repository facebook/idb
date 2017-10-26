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
 @param error an error out for any error that occurs.
 @return a File Reader.
 */
+ (nullable instancetype)readerWithFilePath:(NSString *)filePath consumer:(id<FBFileConsumer>)consumer error:(NSError **)error;

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
 Starts the Consumption of the File.

 @param error an error out for any error that occurs.
 @return YES if the reading started normally, NO otherwise.
 */
- (BOOL)startReadingWithError:(NSError **)error;

/**
 Stops Reading the file.

 @param error an error out for any error that occurs.
 @return YES if the reading terminated normally, NO otherwise.
 */
- (BOOL)stopReadingWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
