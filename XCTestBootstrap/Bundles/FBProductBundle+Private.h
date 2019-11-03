/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
