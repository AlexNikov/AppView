#import <Foundation/Foundation.h>

/// `valueForKey:` raises `NSException` for a missing key. Swift cannot catch that.
id AVOsAppMCPValueForKey(id obj, NSString *key) {
    if (!obj || key.length == 0) {
        return nil;
    }
    @try {
        return [obj valueForKey:key];
    } @catch (NSException *exception) {
        return nil;
    }
}
