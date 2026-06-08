/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAccessibilityCommands.h"

// Accessibility dictionary keys
FBAXKeys const FBAXKeysLabel = @"AXLabel";
FBAXKeys const FBAXKeysFrame = @"AXFrame";
FBAXKeys const FBAXKeysValue = @"AXValue";
FBAXKeys const FBAXKeysUniqueID = @"AXUniqueId";
FBAXKeys const FBAXKeysType = @"type";
FBAXKeys const FBAXKeysTitle = @"title";
FBAXKeys const FBAXKeysFrameDict = @"frame";
FBAXKeys const FBAXKeysHelp = @"help";
FBAXKeys const FBAXKeysEnabled = @"enabled";
FBAXKeys const FBAXKeysCustomActions = @"custom_actions";
FBAXKeys const FBAXKeysRole = @"role";
FBAXKeys const FBAXKeysRoleDescription = @"role_description";
FBAXKeys const FBAXKeysSubrole = @"subrole";
FBAXKeys const FBAXKeysContentRequired = @"content_required";
FBAXKeys const FBAXKeysPID = @"pid";
FBAXKeys const FBAXKeysTraits = @"traits";
FBAXKeys const FBAXKeysExpanded = @"expanded";
FBAXKeys const FBAXKeysPlaceholder = @"placeholder";
FBAXKeys const FBAXKeysHidden = @"hidden";
FBAXKeys const FBAXKeysFocused = @"focused";
FBAXKeys const FBAXKeysIsRemote = @"is_remote";

// Searchable key constants — values match the corresponding FBAXKeys constants
FBAXSearchableKey const FBAXSearchableKeyLabel = @"AXLabel";
FBAXSearchableKey const FBAXSearchableKeyUniqueID = @"AXUniqueId";
FBAXSearchableKey const FBAXSearchableKeyValue = @"AXValue";
FBAXSearchableKey const FBAXSearchableKeyTitle = @"title";
FBAXSearchableKey const FBAXSearchableKeyRole = @"role";
FBAXSearchableKey const FBAXSearchableKeyRoleDescription = @"role_description";
FBAXSearchableKey const FBAXSearchableKeySubrole = @"subrole";
FBAXSearchableKey const FBAXSearchableKeyHelp = @"help";
FBAXSearchableKey const FBAXSearchableKeyPlaceholder = @"placeholder";

NSSet<FBAXKeys> *FBAXKeysDefaultSet(void)
{
  static NSSet<FBAXKeys> *defaultSet;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    defaultSet = [NSSet setWithArray:@[
      FBAXKeysLabel, FBAXKeysFrame, FBAXKeysValue, FBAXKeysUniqueID,
      FBAXKeysType, FBAXKeysTitle, FBAXKeysFrameDict, FBAXKeysHelp,
      FBAXKeysEnabled, FBAXKeysCustomActions, FBAXKeysRole,
      FBAXKeysRoleDescription, FBAXKeysSubrole, FBAXKeysContentRequired,
      FBAXKeysPID, FBAXKeysTraits,
                  ]];
  });
  return defaultSet;
}

// FBAccessibilityRemoteContentOptions and FBAccessibilityRequestOptions are now
// implemented in Swift (FBAccessibilityRequestOptions.swift).
// FBAccessibilityProfilingData and FBAccessibilityElementsResponse are now
// implemented in Swift (FBAccessibilityResponse.swift).
