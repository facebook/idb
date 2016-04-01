/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

@interface FBProductBundleBuilder ()

@property (nonatomic, strong) id<FBFileManager> fileManager;
@property (nonatomic, strong) id<FBCodesignProvider> codesignProvider;
@property (nonatomic, copy) NSString *bundlePath;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *binaryName;
@property (nonatomic, copy) NSString *workingDirectory;

- (Class)productClass;

@end
