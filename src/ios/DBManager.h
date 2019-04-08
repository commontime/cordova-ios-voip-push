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
- (BOOL) addMessage: (NSString*) messageId;
- (BOOL) deleteMessage: (NSString*) messageId;
- (BOOL) exists: (NSString*) messageId;

@end

NS_ASSUME_NONNULL_END