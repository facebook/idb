/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * The request kind `-[AXPTranslator processTranslatorRequest:]` dispatches a reader's batch on, decoded
 * from its jump table: `BridgeAXTranslatorRequestType.multipleAttribute` in `FBSimulatorBridgeProtocol`,
 * which this Objective-C layer cannot import. The attribute numbers a request carries are
 * `BridgeAXTranslatorAttribute`, shared with the host the same way.
 */
typedef NS_ENUM(NSInteger, FBAXPRequestType) {
  /** Carries its attribute list under `parameters[@"attributes"]`; the handler forwards the batch to
      `AXUIElementCopyMultipleAttributeValues`. Passing an array rather than that dictionary throws
      inside the guest and takes the reader down with it. */
  FBAXPRequestTypeMultipleAttribute = 5,
};

NS_ASSUME_NONNULL_END
