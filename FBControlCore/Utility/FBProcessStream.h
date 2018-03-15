/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFileConsumer.h>
#import <FBControlCore/FBiOSTargetFuture.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Protocol that wraps the standard stream stdout, stderr, stdin
 */
@protocol FBStandardStream <NSObject>

/**
 Attaches to the output, returning a NSFileHandle for writing to.

 @return A Future wrapping the File Handle.
 */
- (FBFuture<NSFileHandle *> *)attachToFileHandle;

/**
 Attaches to the output, returning a NSPipe or NSFileHandle for writing to.
 This method will prefer returning a NSPipe since this is more affordant for the NSTask API.

 @return A Future wrapping the Pipe or File Handle.
 */
- (FBFuture<id> *)attachToPipeOrFileHandle;

/**
 Tears down the output.

 @return A Future that resolves when teardown has completed.
 */
- (FBFuture<NSNull *> *)detach;

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
 The Termination Handle Type for Process Output.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeProcessOutput;

/**
 A container object for the output of a process.
 */
@interface FBProcessOutput<WrappedType> : NSObject <FBiOSTargetContinuation, FBStandardStream>

#pragma mark Initializers

/**
 An Output Container for /dev/nul

 @return a Process Output instance.
 */
+ (FBProcessOutput<NSNull *> *)outputForNullDevice;

/**
 An Output Container for a File Path.

 @param filePath the File Path to write to.
 @return a Process Output instance.
 */
+ (FBProcessOutput<NSString *> *)outputForFilePath:(NSString *)filePath;

/**
 An Output Container that passes to File Consumer

 @param fileConsumer the file consumer to write to.
 @return a Process Output instance.
 */
+ (FBProcessOutput<id<FBFileConsumer>> *)outputForFileConsumer:(id<FBFileConsumer>)fileConsumer;

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

#pragma mark Public Methods

/**
 Allows the reciever to be written to via a file instead of via a file handle.
 This is desirable to use when interacting with an API that doesn't support writing to a file handle.

 @return A Future wrapping a FBProcessFileOutput instance.
 */
- (FBFuture<id<FBProcessFileOutput>> *)providedThroughFile;

@end

/**
 A container object for the input of a process.
 */
@interface FBProcessInput<WrappedType> : NSObject <FBStandardStream>

#pragma mark Initializers

/**
 An Output Container that connects a File Consumer to a Pipe.
 The 'contents' field will contain an opaque consumer that can be written to.

 @return a Process Output instance.
 */
+ (FBProcessInput<id<FBFileConsumer>> *)inputProducingConsumer;

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
