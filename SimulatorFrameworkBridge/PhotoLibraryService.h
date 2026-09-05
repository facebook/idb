/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 * Clears the simulator's photo library by deleting assets through PLPhotoLibrary's CoreData context,
 * bypassing the PHPhotoLibrary change-request API (which needs user confirmation). Returns 0 on success.
 */
int handlePhotoLibraryAction(NSString *action);
