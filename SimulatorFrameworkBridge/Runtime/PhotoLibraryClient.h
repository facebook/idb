/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBPhotoLibraryClient : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@property (nonatomic, readonly) NSUInteger assetCount;

- (instancetype)initWithPhotoLibrary:(PHPhotoLibrary *)photoLibrary assets:(PHFetchResult<PHAsset *> *)assets NS_DESIGNATED_INITIALIZER NS_SWIFT_NAME(init(library:assets:));
- (BOOL)deleteAssets;

@end

NS_ASSUME_NONNULL_END
