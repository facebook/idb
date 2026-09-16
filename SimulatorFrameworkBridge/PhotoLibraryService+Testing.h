/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Photos/Photos.h>

NS_ASSUME_NONNULL_BEGIN
int FBPhotoLibraryClearWithLibrary(PHPhotoLibrary *library, PHFetchResult<PHAsset *> *assets);
NS_ASSUME_NONNULL_END
