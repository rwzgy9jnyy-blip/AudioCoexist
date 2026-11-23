#pragma once
#import <objc/runtime.h>

// The test harness supplies a method-replacement implementation.
void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original);
