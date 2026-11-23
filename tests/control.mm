#import <Foundation/Foundation.h>
NSString *ASCTestRoot;
#define main ASCControlMain
#include "../Control.m"
#undef main

int main(int argc, char **argv) {
    @autoreleasepool {
        const char *root = getenv("ASC_TEST_ROOT");
        if (!root || root[0] != '/') return 2;
        ASCTestRoot = @(root);
        return ASCControlMain(argc, argv);
    }
}
