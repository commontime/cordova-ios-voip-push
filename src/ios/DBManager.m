#import "DBManager.h"

static DBManager *sharedInstance = nil;
static sqlite3 *database = nil;
static sqlite3_stmt *statement = nil;

static NSString *DATABASE_NAME = @"IgnoreMessageDB.db";
static NSString *MESSAGE_ID = @"messageid";
static NSString *TABLE_IGNORE = @"messageid";
static NSString *KEY_ID = @"id";
static NSString *DATE = @"date";

@implementation DBManager

+ (DBManager*) getSharedInstance
{
    if (!sharedInstance)
    {
        sharedInstance = [[super allocWithZone: NULL] init];
        [sharedInstance openDB];
        [sharedInstance createDB];
    }
    return sharedInstance;
}

- (BOOL) openDB
{
    NSURL *groupURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier: [NSString stringWithFormat:@"group.%@", [[NSBundle mainBundle] bundleIdentifier]]];
    
    databasePath = [[NSString alloc] initWithString: [[groupURL path] stringByAppendingPathComponent:DATABASE_NAME]];
    
    NSString *docsDir;
    NSArray *dirPaths;
    
    dirPaths = NSSearchPathForDirectoriesInDomains
    (NSDocumentDirectory, NSUserDomainMask, YES);
    docsDir = dirPaths[0];
    
    databasePath = [[NSString alloc] initWithString: [docsDir stringByAppendingPathComponent:DATABASE_NAME]];
    
    const char *dbpath = [databasePath UTF8String];
    if (sqlite3_open(dbpath, &database) == SQLITE_OK)
    {
        return YES;
    }
    else
    {
        NSLog(@"Failed to open/create database");
        return NO;
    }
    return NO;
}

- (void) closeDB
{
    sqlite3_close(database);
}

- (BOOL) createDB
{
    BOOL success = NO;
    const char *dbpath = [databasePath UTF8String];
    if (sqlite3_open(dbpath, &database) == SQLITE_OK)
    {
        char *errMsg;
        if (![self tableExists: TABLE_IGNORE])
        {
            NSString *sql = [NSString stringWithFormat: @"CREATE TABLE %@ ( %@ INTEGER PRIMARY KEY AUTOINCREMENT, %@ TEXT, %@ INTEGER )", TABLE_IGNORE, KEY_ID, MESSAGE_ID, DATE];
            if (sqlite3_exec(database, [sql UTF8String], NULL, NULL, &errMsg) == SQLITE_OK)
            {
                success = YES;
            }
            else
            {
                NSLog(@"Failed to create table");
            }
        }
    }
    else
    {
        NSLog(@"Failed to open/create database");
    }
    return success;
}

- (BOOL) tableExists: (NSString*) tableName
{
    BOOL success = NO;
    NSString *querySQL = [NSString stringWithFormat: @"SELECT COUNT(*) FROM sqlite_master WHERE type = table AND name = %@", tableName];
    const char *query_stmt = [querySQL UTF8String];
    int count = 0;
    if (sqlite3_prepare_v2(database, query_stmt, -1, &statement, NULL) == SQLITE_OK)
    {
        while (sqlite3_step(statement) == SQLITE_ROW)
        {
            count = sqlite3_column_int(statement, 0);
        }
        if (count > 0)
        {
            success = YES;
        }
    }
    sqlite3_finalize(statement);
    return success;
}

- (BOOL) addMessage: (NSString*) messageId;
{
    if ([self exists:messageId]) return NO;
    
    BOOL success = NO;
    
    const char *dbpath = [databasePath UTF8String];
    if (sqlite3_open(dbpath, &database) == SQLITE_OK)
    {
        NSString *insertSQL = [NSString stringWithFormat:@"INSERT INTO %@ (%@, %@) values (\"%@\", \"%@\")", TABLE_IGNORE, MESSAGE_ID, DATE, messageId, [[NSDate alloc] init]];
        const char *insert_stmt = [insertSQL UTF8String];
        sqlite3_prepare_v2(database, insert_stmt,-1, &statement, NULL);
        if (sqlite3_step(statement) == SQLITE_DONE)
        {
            success = YES;
        }
    }
    sqlite3_finalize(statement);
    return success;
}

- (BOOL) deleteMessage: (NSString*) messageId;
{
    BOOL success = NO;
    NSString *querySQL = [NSString stringWithFormat: @"SELECT %@ FROM %@ WHERE %@=\"%@\"", KEY_ID, TABLE_IGNORE, MESSAGE_ID, messageId];
    const char *query_stmt = [querySQL UTF8String];
    if (sqlite3_prepare_v2(database, query_stmt, -1, &statement, NULL) == SQLITE_OK)
    {
        if (sqlite3_step(statement) == SQLITE_ROW)
        {
            int keyId = sqlite3_column_int(statement, 0);
            sqlite3_reset(statement);
            const char *dbpath = [databasePath UTF8String];
            if (sqlite3_open(dbpath, &database) == SQLITE_OK)
            {
                NSString *deleteSQL = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ =%d", TABLE_IGNORE, KEY_ID, keyId];
                const char *delete_stmt = [deleteSQL UTF8String];
                sqlite3_prepare_v2(database, delete_stmt,-1, &statement, NULL);
                if (sqlite3_step(statement) == SQLITE_DONE)
                {
                    success = YES;
                }
            }
        }
    }
    sqlite3_finalize(statement);
    return success;
}

- (BOOL) exists: (NSString*) messageId
{
    BOOL success = NO;
    NSString *querySQL = [NSString stringWithFormat: @"SELECT COUNT(*) FROM %@ WHERE %@=\"%@\"", TABLE_IGNORE, MESSAGE_ID, messageId];
    const char *query_stmt = [querySQL UTF8String];
    int count = 0;
    if (sqlite3_prepare_v2(database, query_stmt, -1, &statement, NULL) == SQLITE_OK)
    {
        while (sqlite3_step(statement) == SQLITE_ROW)
        {
            count = sqlite3_column_int(statement, 0);
        }
        if (count > 0)
        {
            success = YES;
        }
    }
    sqlite3_finalize(statement);
    return success;
}

@end