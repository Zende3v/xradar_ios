#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, EONASystemMediaCommand) {
    EONASystemMediaCommandToggle = 2,
    EONASystemMediaCommandNext = 4,
    EONASystemMediaCommandPrevious = 5,
};

/// Variante interne : commandes du lecteur actif. Aucun entitlement privé ajouté.
@interface EONASystemMedia : NSObject
+ (BOOL)isEnabled NS_SWIFT_NAME(isEnabled());
+ (BOOL)prepare NS_SWIFT_NAME(prepare());
+ (BOOL)send:(EONASystemMediaCommand)command NS_SWIFT_NAME(send(_:));
+ (void)read:(void (^)(NSString * _Nullable title,
                      NSString * _Nullable artist,
                      NSData * _Nullable artwork,
                      NSNumber * _Nullable playing))completion NS_SWIFT_NAME(read(_:));
@end

NS_ASSUME_NONNULL_END
