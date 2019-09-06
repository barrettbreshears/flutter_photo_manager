//
// Created by Caijinglong on 2019-09-06.
//

#import <Photos/Photos.h>
#import "PMManager.h"
#import "PMAssetPathEntity.h"
#import "PHAsset+PHAsset_checkType.h"
#import "PMCacheContainer.h"
#import "ResultHandler.h"
#import "PMLogUtils.h"


@implementation PMManager {
    BOOL __isAuth;
    PMCacheContainer *cacheContainer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        __isAuth = NO;
        cacheContainer = [PMCacheContainer new];
    }

    return self;
}


- (BOOL)isAuth {
    return __isAuth;
}

- (void)setAuth:(BOOL)auth {
    __isAuth = auth;
}

- (NSArray<PMAssetPathEntity *> *)getGalleryList:(int)type {
    NSMutableArray <PMAssetPathEntity *> *array = [NSMutableArray new];

    // type:
    // 0: all , 1: image, 2:video

    PHFetchResult<PHAssetCollection *> *result = [PHAssetCollection
            fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum
                                  subtype:PHAssetCollectionSubtypeSmartAlbumUserLibrary
                                  options:[PHFetchOptions new]];

    PHFetchOptions *options = [PHFetchOptions new];
    if (type == 1) {
        options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeImage];
    } else if (type == 2) {
        options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeVideo];
    } else {
        options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d OR mediaType == %d", PHAssetMediaTypeImage, PHAssetMediaTypeVideo];
    }

    for (PHAssetCollection *collection in result) {
        PHFetchResult<PHAsset *> *fetchResult = [PHAsset fetchAssetsInAssetCollection:collection options:options];

        PMAssetPathEntity *entity = [PMAssetPathEntity
                entityWithId:collection.localIdentifier
                        name:collection.localizedTitle
                  assetCount:(int) fetchResult.count];
        [array addObject:entity];
    }

    return array;
}

- (NSArray<PMAssetEntity *> *)getAssetEntityListWithGalleryId:(NSString *)id
                                                         type:(int)type
                                                         page:(NSUInteger)page
                                                    pageCount:(NSUInteger)pageCount {
    NSMutableArray<PMAssetEntity *> *result = [NSMutableArray new];

    PHFetchOptions *options = [PHFetchOptions new];

    PHFetchResult<PHAssetCollection *> *fetchResult = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[id] options:options];
    if (fetchResult && fetchResult.count == 0) {
        return result;
    }

    // type:
    // 0: all , 1: image, 2:video

    if (type == 1) {
        options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeImage];
    } else if (type == 2) {
        options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeVideo];
    } else {
        options.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d OR mediaType == %d", PHAssetMediaTypeImage, PHAssetMediaTypeVideo];
    }

    PHAssetCollection *collection = fetchResult.firstObject;

    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];

    PHFetchResult<PHAsset *> *assetArray = [PHAsset fetchAssetsInAssetCollection:collection options:options];

    NSUInteger startIndex = page * pageCount;
    NSUInteger endIndex = startIndex + pageCount - 1;

    NSUInteger count = assetArray.count;
    if (endIndex >= count) {
        endIndex = count - 1;
    }

    for (NSUInteger i = startIndex; i <= endIndex; i++) {
        PHAsset *asset = assetArray[i];
        PMAssetEntity *entity = [self convertPHAssetToAssetEntity:asset];
        [result addObject:entity];
        [cacheContainer putAssetEntity:entity];
    }

    return result;
}

- (PMAssetEntity *)convertPHAssetToAssetEntity:(PHAsset *)asset {
    // type:
    // 0: all , 1: image, 2:video

    int type = 0;
    if (asset.isImage) {
        type = 1;
    } else if (asset.isVideo) {
        type = 2;
    }

    NSDate *date = asset.creationDate;
    long createDt = (long) (date.timeIntervalSince1970 / 1000);

    PMAssetEntity *entity = [PMAssetEntity entityWithId:asset.localIdentifier
                                               createDt:createDt width:asset.pixelWidth
                                                 height:asset.pixelHeight duration:(long) asset.duration type:type];
    entity.phAsset = asset;
    return entity;
}

- (PMAssetEntity *)getAssetEntity:(NSString *)assetId {
    PMAssetEntity *entity = [cacheContainer getAssetEntity:assetId];
    if (entity) {
        return entity;
    }
    PHFetchResult<PHAsset *> *result = [PHAsset fetchAssetsWithLocalIdentifiers:@[assetId] options:nil];
    if (result == nil || result.count == 0) {
        return nil;
    }

    PHAsset *asset = result[0];
    entity = [self convertPHAssetToAssetEntity:asset];
    [cacheContainer putAssetEntity:entity];
    return entity;
}

- (void)clearCache {
    [cacheContainer clearCache];
}

- (void)getThumbWithId:(NSString *)id width:(NSUInteger)width height:(NSUInteger)height
         resultHandler:(ResultHandler *)handler {
    PMAssetEntity *entity = [self getAssetEntity:id];
    if (entity && entity.phAsset) {
        PHAsset *asset = entity.phAsset;
        [self fetchThumb:asset width:width height:height resultHandler:handler];
    } else {
        [handler replyError:@"asset is not found"];
    }
}

- (void)fetchThumb:(PHAsset *)asset width:(NSUInteger)width height:(NSUInteger)height
     resultHandler:(ResultHandler *)handler {

    PHImageManager *manager = PHImageManager.defaultManager;
    PHImageRequestOptions *options = [PHImageRequestOptions new];
    [options setNetworkAccessAllowed:YES];
    [options setProgressHandler:^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        if (progress == 1.0) {
            [self fetchThumb:asset width:width height:height resultHandler:handler];
        }
    }];
    [manager requestImageForAsset:asset targetSize:CGSizeMake(width, height) contentMode:PHImageContentModeAspectFill options:options resultHandler:^(UIImage *result, NSDictionary *info) {

        BOOL downloadFinished = [PMManager isDownloadFinish:info];

        if (!downloadFinished) {
            return;
        }

        if ([handler isReplied]) {
            return;
        }

        NSData *imageData = UIImageJPEGRepresentation(result, 0.95);
        FlutterStandardTypedData *data = [FlutterStandardTypedData typedDataWithBytes:imageData];
        [handler reply:data];
    }];
}

- (void)getFullSizeFileWithId:(NSString *)id resultHandler:(ResultHandler *)handler {
    PMAssetEntity *entity = [self getAssetEntity:id];
    if (entity && entity.phAsset) {
        PHAsset *asset = entity.phAsset;
        if (asset.isVideo) {
            [self fetchFullSizeVideo:asset handler:handler];
            return;
        } else {
            [self fetchFullSize:asset resultHandler:handler];
        }
    } else {
        [handler replyError:@"asset is not found"];
    }
}

- (void)fetchFullSizeVideo:(PHAsset *)asset handler:(ResultHandler *)handler {
    NSString *homePath = NSTemporaryDirectory();
    NSFileManager *manager = NSFileManager.defaultManager;

    NSMutableString *path = [NSMutableString stringWithString:homePath];

    NSString *filename = [asset valueForKey:@"filename"];

    NSString *dirPath = [NSString stringWithFormat:@"%@/%@", homePath, @".video"];
    [manager createDirectoryAtPath:dirPath attributes:@{}];

    [path appendFormat:@"%@/%@", @".video", filename];
    PHVideoRequestOptions *options = [PHVideoRequestOptions new];
    if ([manager fileExistsAtPath:path]) {
        [[PMLogUtils sharedInstance] info:[NSString stringWithFormat:@"read cache from %@", path]];
        [handler reply:path];
        return;
    }

    [options setProgressHandler:^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        if (progress == 1.0) {
            [self fetchFullSizeVideo:asset handler:handler];
        }
    }];

    [options setNetworkAccessAllowed:YES];

    [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:options resultHandler:^(AVAsset *_Nullable asset, AVAudioMix *_Nullable audioMix,
            NSDictionary *_Nullable info) {

        BOOL downloadFinish = [PMManager isDownloadFinish:info];

        if (!downloadFinish) {
            return;
        }

        NSString *preset = AVAssetExportPresetHighestQuality;
        AVAssetExportSession *exportSession = [AVAssetExportSession exportSessionWithAsset:asset presetName:preset];
        if (exportSession) {
            exportSession.outputFileType = AVFileTypeMPEG4;
            exportSession.outputURL = [NSURL fileURLWithPath:path];
            [exportSession exportAsynchronouslyWithCompletionHandler:^{
                [handler reply:path];
            }];
        } else {
            [handler reply:NULL];
        }

    }];
}

- (void)fetchFullSize:(PHAsset *)asset resultHandler:(ResultHandler *)handler {
    PHImageManager *manager = PHImageManager.defaultManager;
    PHImageRequestOptions *options = [PHImageRequestOptions new];


    [options setNetworkAccessAllowed:YES];
    [options setProgressHandler:^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        if (progress == 1.0) {
            [self fetchFullSize:asset resultHandler:handler];
        }
    }];
    [manager requestImageDataForAsset:asset options:options resultHandler:^(NSData *imageData, NSString *dataUTI, UIImageOrientation orientation, NSDictionary *info) {

        BOOL downloadFinished = [PMManager isDownloadFinish:info];
        if (!downloadFinished) {
            return;
        }

        if ([handler isReplied]) {
            return;
        }

        FlutterStandardTypedData *data = [FlutterStandardTypedData typedDataWithBytes:imageData];

        [handler reply:data];
    }];
}

+ (BOOL)isDownloadFinish:(NSDictionary *)info {
    return ![info[PHImageCancelledKey] boolValue] && !info[PHImageErrorKey] && ![info[PHImageResultIsDegradedKey] boolValue];
}

@end