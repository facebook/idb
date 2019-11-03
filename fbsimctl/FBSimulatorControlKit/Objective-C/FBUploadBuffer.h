/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBUploadBuffer;

/**
 The Action Types for a Binary Transfer.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeBinaryTransfer;
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeUploadedBinary;

/**
 An Action defining the transmission of binary data.
 */
@interface FBUploadHeader : NSObject <FBiOSTargetFuture, NSCopying>

/**
 The Designated Initializer.

 @param extension the path extension to be uploaded.
 @param size the size of the header.
 @return a new Binary Header.
 */
+ (instancetype)headerWithPathExtension:(NSString *)extension size:(size_t)size;

/**
 The Path Extension of the Binary.
 */
@property (nonatomic, copy, readonly) NSString *extension;

/**
 The Size of the Header in bytes.
 */
@property (nonatomic, assign, readonly) size_t size;

@end

/**
 Describes the Location of an Uploaded Binary.
 */
@interface FBUploadedDestination : NSObject <FBiOSTargetFuture, NSCopying>

/**
 The Designated Initializer

 @param header the header the binary was uploaded with.
 @param path the path on the remote end
 @return a new Uploaded Binary.
 */
+ (instancetype)destinationWithHeader:(FBUploadHeader *)header path:(NSString *)path;

/**
 The Header uploaded with.
 */
@property (nonatomic, copy, readonly) FBUploadHeader *header;

/**
 The Path of the Uploaded Binary.
 */
@property (nonatomic, copy, readonly) NSString *path;

/**
 The Data backing the path.
 */
@property (nonatomic, copy, readonly, nullable) NSData *data;

@end

/**
 Buffers a binary that can yield when done.
 */
@interface FBUploadBuffer : NSObject

/**
 Creates a new Binary Buffer with the given capacity.

 @param header the header from which to make a buffer.
 @param workingDirectory the Working Directory to write to.
 @return a new Binary Buffer.
 */
+ (nullable)bufferWithHeader:(FBUploadHeader *)header workingDirectory:(NSString *)workingDirectory;

/**
 Write the data to the buffer.

 @param input the input data to write.
 @param remainderOut any additional data at the trailing end of the buffer.
 @return the Uploaded Binary if finished, nil if not finished.
 */
- (nullable FBUploadedDestination *)writeData:(NSData *)input remainderOut:(NSData *_Nullable*_Nullable)remainderOut;

@end

NS_ASSUME_NONNULL_END
