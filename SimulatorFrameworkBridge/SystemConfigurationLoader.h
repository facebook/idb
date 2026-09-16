/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

void *_Nullable FBSystemConfigurationLoad(void);
void *_Nullable FBSystemConfigurationLookup(void *library, const char *symbol);

/** Overrides symbol loading for synchronous service tests. Pass nil to restore the system loader. */
void FBSystemConfigurationSetLoaderForTesting(
  void *_Nullable (^_Nullable load)(void),
  void *_Nullable (^_Nullable lookup)(void *library, const char *symbol));

NS_ASSUME_NONNULL_END
