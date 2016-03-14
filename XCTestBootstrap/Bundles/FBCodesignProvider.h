// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

/**
 Used for codesigning bundles
 */
@protocol FBCodesignProvider <NSObject>

/**
 Request to codesign bundle at given path

 @param bundlePath path to bundle that should be signed
 @return YES if operation was successful
 */
- (BOOL)signBundleAtPath:(NSString *)bundlePath;

@end
