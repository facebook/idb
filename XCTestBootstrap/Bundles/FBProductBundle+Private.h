// Copyright 2004-present Facebook. All Rights Reserved.

@interface FBProductBundleBuilder ()

@property (nonatomic, strong) id<FBFileManager> fileManager;
@property (nonatomic, strong) id<FBCodesignProvider> codesignProvider;
@property (nonatomic, copy) NSString *bundlePath;
@property (nonatomic, copy) NSString *workingDirectory;

- (Class)productClass;

@end
