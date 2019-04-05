#import <Foundation/Foundation.h>
#import <sqlite3.h>

NS_ASSUME_NONNULL_BEGIN

@interface DBManager : NSObject {
    NSString *databasePath;
}

+ (DBManager*) getSharedInstance;
- (BOOL) openDB;
- (void) closeDB;
- (BOOL) createDB;
- (BOOL) addMessage: (long) messageId;
- (BOOL) deleteMessage: (long) messageId;
- (BOOL) exists: (long) messageId;

@end

NS_ASSUME_NONNULL_END
