// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCoreError.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Error Domain for idb.
 */
extern NSString *const FBIDBErrorDomain;

/**
 Helpers for constructing Errors representing errors in idb & adding additional diagnosis.
 */
@interface FBIDBError : FBControlCoreError

@end

NS_ASSUME_NONNULL_END
