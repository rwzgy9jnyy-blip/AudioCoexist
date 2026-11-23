#pragma once
#import <Foundation/Foundation.h>

// Host-only filesystem mapping. Production builds resolve the real RootHide SDK.
extern NSString *ASCTestRoot;
static inline NSString *jbroot(NSString *path) {
    return [ASCTestRoot stringByAppendingString:path];
}
static inline const char *jbroot(const char *path) {
    return jbroot(@(path)).fileSystemRepresentation;
}
