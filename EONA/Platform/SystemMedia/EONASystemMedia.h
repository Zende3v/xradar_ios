#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, EONASystemMediaCommand) {
    EONASystemMediaCommandToggle = 2,
    EONASystemMediaCommandNext = 4,
    EONASystemMediaCommandPrevious = 5,
    EONASystemMediaCommandSkipForward = 17,
    EONASystemMediaCommandSkipBackward = 18,
};

/// Relevé facultatif : nil signifie information inaccessible, jamais refus inventé.
@interface EONASystemMediaSnapshot : NSObject
@property (nonatomic, readonly, copy, nullable) NSString *title;
@property (nonatomic, readonly, copy, nullable) NSString *artist;
@property (nonatomic, readonly, copy, nullable) NSData *artwork;
@property (nonatomic, readonly, strong, nullable) NSNumber *playing;
@property (nonatomic, readonly, copy, nullable) NSDictionary<NSNumber *, NSNumber *> *commands;
@property (nonatomic, readonly, strong, nullable) NSNumber *forwardInterval;
@property (nonatomic, readonly, strong, nullable) NSNumber *backwardInterval;
@end

/// Variante interne : commandes du lecteur actif. Aucun entitlement privé ajouté.
@interface EONASystemMedia : NSObject
+ (BOOL)isEnabled NS_SWIFT_NAME(isEnabled());
+ (BOOL)prepare NS_SWIFT_NAME(prepare());
+ (BOOL)send:(EONASystemMediaCommand)command
    interval:(NSNumber * _Nullable)interval
  completion:(void (^)(NSNumber * _Nullable error, NSArray<NSNumber *> * _Nullable statuses))completion
    NS_SWIFT_NAME(send(_:interval:completion:));
+ (void)read:(void (^)(EONASystemMediaSnapshot *snapshot))completion NS_SWIFT_NAME(read(_:));
+ (void)beginObserving:(void (^)(void))changed NS_SWIFT_NAME(beginObserving(_:));
+ (void)endObserving NS_SWIFT_NAME(endObserving());
@end

NS_ASSUME_NONNULL_END
