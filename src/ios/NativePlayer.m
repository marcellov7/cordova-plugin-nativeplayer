#import <Cordova/CDV.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface NativePlayer : CDVPlugin <AVPictureInPictureControllerDelegate>

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) AVPictureInPictureController *pipController;
@property (nonatomic, strong) id timeObserver;
@property (nonatomic, strong) NSString *callbackId;
@property (nonatomic, strong) NSString *divId;
@property (nonatomic, assign) BOOL isFullscreen;

@end

@implementation NativePlayer

- (void)pluginInitialize {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)createPlayer:(CDVInvokedUrlCommand*)command {
    self.callbackId = command.callbackId;
    NSString* url = [command.arguments objectAtIndex:0];
    self.divId = [command.arguments objectAtIndex:1];

    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *videoURL = [NSURL URLWithString:url];
        AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:videoURL];
        self.player = [AVPlayer playerWithPlayerItem:playerItem];
        self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
        [self.webView.superview.layer addSublayer:self.playerLayer];

        [self setupPlayerListeners];
        [self updatePlayerPosition];
        [self setupPictureInPicture];

        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    });
}

- (void)setupPlayerListeners {
    [self.player addObserver:self forKeyPath:@"timeControlStatus" options:NSKeyValueObservingOptionNew context:nil];
    [self.player addObserver:self forKeyPath:@"rate" options:NSKeyValueObservingOptionNew context:nil];
    [self.player.currentItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    [self.player.currentItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
    [self.player.currentItem addObserver:self forKeyPath:@"presentationSize" options:NSKeyValueObservingOptionNew context:nil];

    __weak typeof(self) weakSelf = self;
    self.timeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        [weakSelf sendEventWithName:@"timeUpdate" body:@{
            @"currentTime": @(CMTimeGetSeconds(time)),
            @"duration": @(CMTimeGetSeconds(weakSelf.player.currentItem.duration))
        }];
    }];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemFailedToPlayToEndTime:)
                                                 name:AVPlayerItemFailedToPlayToEndTimeNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioSessionInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"timeControlStatus"]) {
        AVPlayerTimeControlStatus status = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
        switch (status) {
            case AVPlayerTimeControlStatusPaused:
                [self sendEventWithName:@"pause" body:nil];
                break;
            case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
                [self sendEventWithName:@"waiting" body:nil];
                break;
            case AVPlayerTimeControlStatusPlaying:
                [self sendEventWithName:@"play" body:nil];
                break;
        }
    } else if ([keyPath isEqualToString:@"rate"]) {
        float rate = [[change objectForKey:NSKeyValueChangeNewKey] floatValue];
        [self sendEventWithName:@"rateChange" body:@{@"rate": @(rate)}];
    } else if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItemStatus status = [[change objectForKey:NSKeyValueChangeNewKey] integerValue];
        switch (status) {
            case AVPlayerItemStatusReadyToPlay:
                [self sendEventWithName:@"canPlay" body:nil];
                break;
            case AVPlayerItemStatusFailed:
                [self sendEventWithName:@"error" body:@{@"error": self.player.currentItem.error.localizedDescription}];
                break;
        }
    } else if ([keyPath isEqualToString:@"loadedTimeRanges"]) {
        NSArray *loadedTimeRanges = [self.player.currentItem loadedTimeRanges];
        if (loadedTimeRanges.count > 0) {
            CMTimeRange timeRange = [[loadedTimeRanges objectAtIndex:0] CMTimeRangeValue];
            float duration = CMTimeGetSeconds(self.player.currentItem.duration);
            float loadedDuration = CMTimeGetSeconds(timeRange.start) + CMTimeGetSeconds(timeRange.duration);
            float progress = (duration > 0) ? loadedDuration / duration : 0;
            [self sendEventWithName:@"progress" body:@{@"bufferedPercentage": @(progress * 100)}];
        }
    } else if ([keyPath isEqualToString:@"presentationSize"]) {
        CGSize size = self.player.currentItem.presentationSize;
        [self sendEventWithName:@"resolutionChange" body:@{
            @"width": @(size.width),
            @"height": @(size.height)
        }];
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    [self sendEventWithName:@"ended" body:nil];
}

- (void)playerItemFailedToPlayToEndTime:(NSNotification *)notification {
    NSError *error = notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
    [self sendEventWithName:@"error" body:@{@"error": error.localizedDescription}];
}

- (void)audioSessionInterruption:(NSNotification *)notification {
    NSInteger type = [[notification.userInfo valueForKey:AVAudioSessionInterruptionTypeKey] integerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        [self sendEventWithName:@"pause" body:nil];
    } else if (type == AVAudioSessionInterruptionTypeEnded) {
        NSInteger option = [[notification.userInfo valueForKey:AVAudioSessionInterruptionOptionKey] integerValue];
        if (option == AVAudioSessionInterruptionOptionShouldResume) {
            [self sendEventWithName:@"play" body:nil];
        }
    }
}

- (void)sendEventWithName:(NSString *)name body:(NSDictionary *)body {
    if (!body) {
        body = @{};
    }
    NSMutableDictionary *event = [NSMutableDictionary dictionaryWithDictionary:body];
    [event setObject:name forKey:@"type"];

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:event];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
}

- (void)updatePlayerPosition {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.commandDelegate evalJs:[NSString stringWithFormat:@"function getElementRect(id) { var el = document.getElementById(id); var rect = el.getBoundingClientRect(); return {left: rect.left, top: rect.top, width: rect.width, height: rect.height}; } getElementRect('%@');", self.divId]
                   completionHandler:^(NSString * _Nullable result, NSError * _Nullable error) {
            if (!error) {
                NSData *jsonData = [result dataUsingEncoding:NSUTF8StringEncoding];
                NSDictionary *rect = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
                if (rect) {
                    self.playerLayer.frame = CGRectMake([rect[@"left"] floatValue],
                                                        [rect[@"top"] floatValue],
                                                        [rect[@"width"] floatValue],
                                                        [rect[@"height"] floatValue]);
                    [self sendEventWithName:@"resize" body:nil];
                }
            }
        }];
    });
}

- (void)setupPictureInPicture {
    if ([AVPictureInPictureController isPictureInPictureSupported]) {
        self.pipController = [[AVPictureInPictureController alloc] initWithPlayerLayer:self.playerLayer];
        self.pipController.delegate = self;
    }
}

- (void)pictureInPictureControllerWillStartPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    [self sendEventWithName:@"pictureInPictureChange" body:@{@"isPictureInPicture": @YES}];
}

- (void)pictureInPictureControllerDidStopPictureInPicture:(AVPictureInPictureController *)pictureInPictureController {
    [self sendEventWithName:@"pictureInPictureChange" body:@{@"isPictureInPicture": @NO}];
}

- (void)play:(CDVInvokedUrlCommand*)command {
    [self.player play];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)pause:(CDVInvokedUrlCommand*)command {
    [self.player pause];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)stop:(CDVInvokedUrlCommand*)command {
    [self.player pause];
    [self.player seekToTime:kCMTimeZero];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)seekTo:(CDVInvokedUrlCommand*)command {
    NSNumber* position = [command.arguments objectAtIndex:0];
    [self.player seekToTime:CMTimeMakeWithSeconds([position doubleValue], NSEC_PER_SEC)];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setVolume:(CDVInvokedUrlCommand*)command {
    NSNumber* volume = [command.arguments objectAtIndex:0];
    self.player.volume = [volume floatValue];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setRate:(CDVInvokedUrlCommand*)command {
    NSNumber* rate = [command.arguments objectAtIndex:0];
    self.player.rate = [rate floatValue];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)toggleFullscreen:(CDVInvokedUrlCommand*)command {
    self.isFullscreen = !self.isFullscreen;
    if (self.isFullscreen) {
        // Implement fullscreen logic
    } else {
        // Implement exit fullscreen logic
    }
    [self sendEventWithName:@"fullscreenChange" body:@{@"isFullscreen": @(self.isFullscreen)}];
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)togglePictureInPicture:(CDVInvokedUrlCommand*)command {
    if (self.pipController) {
        if (self.pipController.isPictureInPictureActive) {
            [self.pipController stopPictureInPicture];
        } else {
            [self.pipController startPictureInPicture];
        }
    }
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setPreferredAudioLanguage:(CDVInvokedUrlCommand*)command {
    NSString* language = [command.arguments objectAtIndex:0];
    AVMediaSelectionGroup *audioGroup = [self.player.currentItem.asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicAudible];
    AVMediaSelectionOption *languageOption = [AVMediaSelectionGroup mediaSelectionOptionWithPropertyList:language inMediaSelectionGroup:audioGroup];
    if (languageOption) {
        [self.player.currentItem selectMediaOption:languageOption inMediaSelectionGroup:audioGroup];
    }
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setPreferredTextLanguage:(CDVInvokedUrlCommand*)command {
    NSString* language = [command.arguments objectAtIndex:0];
    AVMediaSelectionGroup *subtitleGroup = [self.player.currentItem.asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicLegible];
    AVMediaSelectionOption *languageOption = [AVMediaSelectionGroup mediaSelectionOptionWithPropertyList:language inMediaSelectionGroup:subtitleGroup];
    if (languageOption) {
        [self.player.currentItem selectMediaOption:languageOption inMediaSelectionGroup:subtitleGroup];
    }
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)enableSubtitles:(CDVInvokedUrlCommand*)command {
    BOOL enable = [[command.arguments objectAtIndex:0] boolValue];
    AVMediaSelectionGroup *subtitleGroup = [self.player.currentItem.asset mediaSelectionGroupForMediaCharacteristic:AVMediaCharacteristicLegible];
    if (enable) {
        AVMediaSelectionOption *option = subtitleGroup.options.firstObject;
        [self.player.currentItem selectMediaOption:option inMediaSelectionGroup:subtitleGroup];
    } else {
        [self.player.currentItem selectMediaOption:nil inMediaSelectionGroup:subtitleGroup];
    }
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setVideoQuality:(CDVInvokedUrlCommand*)command {
    NSString* quality = [command.arguments objectAtIndex:0];
    AVPlayerItem *playerItem = self.player.currentItem;
    NSArray *videoAssetTracks = [playerItem.asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoAssetTracks.count > 0) {
        AVAssetTrack *videoTrack = videoAssetTracks.firstObject;
        NSArray *formatDescriptions = [videoTrack formatDescriptions];
        for (CMFormatDescriptionRef desc in formatDescriptions) {
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(desc);
            NSString *currentQuality = [NSString stringWithFormat:@"%dp", dimensions.height];
            if ([currentQuality isEqualToString:quality]) {
                AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
                videoComposition.renderSize = CGSizeMake(dimensions.width, dimensions.height);
                videoComposition.frameDuration = CMTimeMake(1, 30);
                AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
                instruction.timeRange = CMTimeRangeMake(kCMTimeZero, [playerItem.asset duration]);
                AVMutableVideoCompositionLayerInstruction *layerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
                instruction.layerInstructions = @[layerInstruction];
                videoComposition.instructions = @[instruction];
                playerItem.videoComposition = videoComposition;
                break;
            }
        }
    }
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setBackgroundPlayback:(CDVInvokedUrlCommand*)command {
    BOOL enabled = [[command.arguments objectAtIndex:0] boolValue];
    NSError *error = nil;
    if (enabled) {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&error];
    } else {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:&error];
    }
    if (error) {
        [self sendEventWithName:@"warning" body:@{@"message": [NSString stringWithFormat:@"Error setting audio session category: %@", error.localizedDescription]}];
    }
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)updateMediaInfo {
    AVPlayerItem *playerItem = self.player.currentItem;
    if (playerItem) {
        NSMutableDictionary *mediaInfo = [NSMutableDictionary dictionary];
        [mediaInfo setObject:@(CMTimeGetSeconds(playerItem.duration)) forKey:@"duration"];

        NSArray *metadataItems = playerItem.asset.commonMetadata;
        for (AVMetadataItem *item in metadataItems) {
            if ([item.commonKey isEqualToString:AVMetadataCommonKeyTitle]) {
                [mediaInfo setObject:item.value forKey:@"title"];
            } else if ([item.commonKey isEqualToString:AVMetadataCommonKeyArtist]) {
                [mediaInfo setObject:item.value forKey:@"artist"];
            } else if ([item.commonKey isEqualToString:AVMetadataCommonKeyAlbumName]) {
                [mediaInfo setObject:item.value forKey:@"album"];
            }
        }

        [self sendEventWithName:@"mediaInfo" body:mediaInfo];
    }
}

- (void)handleStalled {
    if (self.player.currentItem.playbackLikelyToKeepUp == NO &&
        self.player.currentItem.playbackBufferEmpty == YES) {
        [self sendEventWithName:@"stalled" body:nil];
    }
}

- (void)applicationWillResignActive:(NSNotification *)notification {
    [self.player pause];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self.player play];
}

- (void)dealloc {
    [self.player removeObserver:self forKeyPath:@"timeControlStatus"];
    [self.player removeObserver:self forKeyPath:@"rate"];
    [self.player.currentItem removeObserver:self forKeyPath:@"status"];
    [self.player.currentItem removeObserver:self forKeyPath:@"loadedTimeRanges"];
    [self.player.currentItem removeObserver:self forKeyPath:@"presentationSize"];

    if (self.timeObserver) {
        [self.player removeTimeObserver:self.timeObserver];
    }

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end