#ifndef IDB_DIRECT_ERROR_MAPPING_H
#define IDB_DIRECT_ERROR_MAPPING_H

#import <Foundation/Foundation.h>
#import "idb_direct.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Maps NSError to idb_error_t with comprehensive error code coverage
 * @param error The NSError to map (can be nil)
 * @return Appropriate idb_error_t value
 */
idb_error_t idb_map_nserror_to_idb_error(NSError* _Nullable error);

/**
 * Returns detailed error string for any idb_error_t, including extended codes
 * @param error The error code
 * @return Human-readable error description
 */
const char* _Nonnull idb_detailed_error_string(idb_error_t error);

/**
 * Validates that all possible error codes are properly mapped
 * Used for testing to ensure comprehensive error coverage
 * @return YES if all error codes are properly handled
 */
BOOL idb_validate_error_mapping(void);

#ifdef __cplusplus
}
#endif

#endif // IDB_DIRECT_ERROR_MAPPING_H