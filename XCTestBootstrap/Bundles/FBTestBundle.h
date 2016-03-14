// Copyright 2004-present Facebook. All Rights Reserved.

#import <XCTestBootstrap/FBProductBundle.h>

@class FBTestConfiguration;

/**
 Represents test bundle (aka .xctest)
 */
@interface FBTestBundle : FBProductBundle

/**
 The current test configuration file for test bundle
 */
@property (nonatomic, strong, readonly) FBTestConfiguration *configuration;

@end


/**
 Prepares FBTestBundle by:
 - coping it to workingDirectory, if set
 - creating and saving test configuration file if sessionIdentifier is set
 - codesigning bundle with codesigner, if set
 - loading bundle information from Info.plist file
 */
@interface FBTestBundleBuilder : FBProductBundleBuilder

/**
 @param sessionIdentifier session identifier for test configuration
 @return builder
 */
- (instancetype)withSessionIdentifier:(NSUUID *)sessionIdentifier;

/**
 @return prepared test bundle
 */
- (FBTestBundle *)build;

@end
