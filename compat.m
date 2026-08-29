#import <Foundation/Foundation.h>

int __isOSVersionAtLeast(int major, int minor, int patch) {
    NSOperatingSystemVersion v = {major, minor, patch};
    return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:v];
}
