/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Contacts/Contacts.h>

NS_ASSUME_NONNULL_BEGIN

int FBContactsClearWithStore(CNContactStore *store, CNSaveRequest *(^makeSaveRequest)(void));

NS_ASSUME_NONNULL_END
