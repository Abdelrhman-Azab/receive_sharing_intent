#if __has_include(<Flutter/Flutter.h>)
#import <Flutter/Flutter.h>
@interface ReceiveSharingIntentPlugin : NSObject<FlutterPlugin>
@end
#else
#import <Foundation/Foundation.h>
@interface ReceiveSharingIntentPlugin : NSObject
@end
#endif
