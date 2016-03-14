// Copyright 2004-present Facebook. All Rights Reserved.

#import <XCTestBootstrap/FBCodesignProvider.h>

/**
 Used for codesigning bundles
 */
@interface FBCodeSignCommand : NSObject <FBCodesignProvider>

/**
 Identity used to codesign bundle
 */
@property (nonatomic, copy, readonly) NSString *identityName;

/**
 @param identityName identity used to codesign bundle
 @return code sign command that signs bundles with given identity
 */
+ (instancetype)codeSignCommandWithIdentityName:(NSString *)identityName;

@end
