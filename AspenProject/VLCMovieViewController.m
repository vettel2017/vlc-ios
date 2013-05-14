//
//  VLCMovieViewController.m
//  AspenProject
//
//  Created by Felix Paul Kühne on 27.02.13.
//  Copyright (c) 2013 VideoLAN. All rights reserved.
//

#import "VLCMovieViewController.h"
#import "VLCExternalDisplayController.h"

#define INPUT_RATE_DEFAULT  1000.

@interface VLCMovieViewController () <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UIPopoverController *masterPopoverController;
@property (nonatomic, strong) UIWindow *externalWindow;
@end

@implementation VLCMovieViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Managing the media item

- (void)setMediaItem:(id)newMediaItem
{
    if (_mediaItem != newMediaItem)
        _mediaItem = newMediaItem;

    if (self.masterPopoverController != nil)
        [self.masterPopoverController dismissPopoverAnimated:YES];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.wantsFullScreenLayout = YES;

    _mediaPlayer = [[VLCMediaPlayer alloc] init];
    [_mediaPlayer setDelegate:self];
    [_mediaPlayer setDrawable:self.movieView];

    self.videoFilterView.hidden = YES;
    _videoFiltersHidden = YES;
    _hueLabel.text = NSLocalizedString(@"VFILTER_HUE", @"");
    _contrastLabel.text = NSLocalizedString(@"VFILTER_CONTRAST", @"");
    _brightnessLabel.text = NSLocalizedString(@"VFILTER_BRIGHTNESS", @"");
    _saturationLabel.text = NSLocalizedString(@"VFILTER_SATURATION", @"");
    _gammaLabel.text = NSLocalizedString(@"VFILTER_GAMMA", @"");

    self.playbackView.hidden = YES;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(handleExternalScreenDidConnect:)
                   name:UIScreenDidConnectNotification object:nil];
    [center addObserver:self selector:@selector(handleExternalScreenDidDisconnect:)
                   name:UIScreenDidDisconnectNotification object:nil];
    [center addObserver:self selector:@selector(appWillResign:) name:UIApplicationWillResignActiveNotification object:nil];

    _playingExternallyTitle.text = NSLocalizedString(@"PLAYING_EXTERNALLY_TITLE", @"");
    _playingExternallyDescription.text = NSLocalizedString(@"PLAYING_EXTERNALLY_DESC", @"");
    if ([self hasExternalDisplay])
        [self showOnExternalDisplay];

    _movieView.userInteractionEnabled = NO;
    UITapGestureRecognizer *recognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toogleControlsVisible)];
    recognizer.delegate = self;
    [self.view addGestureRecognizer:recognizer];

    [self resetIdleTimer];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
        [UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleBlackTranslucent;

    if (!self.mediaItem && !self.url)
        return;

    if (self.mediaItem) {
        self.title = [self.mediaItem title];
        [_mediaPlayer setMedia:[VLCMedia mediaWithURL:[NSURL URLWithString:self.mediaItem.url]]];
    } else {
        [_mediaPlayer setMedia:[VLCMedia mediaWithURL:self.url]];
        self.title = @"Network Stream";
    }

    [_mediaPlayer play];

    if (self.mediaItem.lastPosition && [self.mediaItem.lastPosition floatValue] < 0.99)
        [_mediaPlayer setPosition:[self.mediaItem.lastPosition floatValue]];
    self.playbackSpeedSlider.value = [self _playbackSpeed];
    [self _updatePlaybackSpeedIndicator];
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (_idleTimer)
        [_idleTimer invalidate];
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    [UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleBlackOpaque;
    [_mediaPlayer pause];
    [super viewWillDisappear:animated];
    self.mediaItem.lastPosition = @([_mediaPlayer position]);
    [_mediaPlayer stop];
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
        self.title = @"Video Playback";
    return self;
}

#pragma mark - controls visibility

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if (touch.view != self.view)
        return NO;

    return YES;
}

- (void)toogleControlsVisible
{
    _controlsHidden = !_controlsHidden;
    CGFloat alpha = _controlsHidden? 0.0f: 1.0f;

    if (!_controlsHidden) {
        _controllerPanel.alpha = 0.0f;
        _controllerPanel.hidden = !_videoFiltersHidden || !_playbackViewHidden;
        _toolbar.alpha = 0.0f;
        _toolbar.hidden = NO;
        _videoFilterView.alpha = 0.0f;
        _videoFilterView.hidden = _videoFiltersHidden;
        _videoFilterButton.alpha = 0.0f;
        _videoFilterButton.hidden = NO;
        _playbackView.alpha = 0.0f;
        _playbackView.hidden = _playbackViewHidden;
        _playbackButton.alpha = 0.0f;
        _playbackButton.hidden = NO;
    }

    void (^animationBlock)() = ^() {
        _controllerPanel.alpha = alpha;
        _toolbar.alpha = alpha;
        _videoFilterView.alpha = alpha;
        _videoFilterButton.alpha = alpha;
        _playbackView.alpha = alpha;
        _playbackButton.alpha = alpha;
    };

    void (^completionBlock)(BOOL finished) = ^(BOOL finished) {
        if (_videoFiltersHidden && _playbackViewHidden)
            _controllerPanel.hidden = _controlsHidden;
        else
            _controllerPanel.hidden = YES;
        _toolbar.hidden = _controlsHidden;
        _videoFilterView.hidden = _videoFiltersHidden;
        _videoFilterButton.hidden = _controlsHidden;
        _playbackView.hidden = _playbackViewHidden;
        _playbackButton.hidden = _controlsHidden;
    };

    [UIView animateWithDuration:0.3f animations:animationBlock completion:completionBlock];
    [[UIApplication sharedApplication] setStatusBarHidden:_controlsHidden withAnimation:UIStatusBarAnimationFade];
}

- (void)resetIdleTimer
{
    if (!_idleTimer)
        _idleTimer = [NSTimer scheduledTimerWithTimeInterval:2.
                                                      target:self
                                                    selector:@selector(idleTimerExceeded)
                                                    userInfo:nil
                                                     repeats:NO];
    else {
        if (fabs([_idleTimer.fireDate timeIntervalSinceNow]) < 2.)
            [_idleTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:2.]];
    }
}

- (void)idleTimerExceeded
{
    _idleTimer = nil;
    if (!_controlsHidden)
        [self toogleControlsVisible];
}

- (UIResponder *)nextResponder
{
    [self resetIdleTimer];
    return [super nextResponder];
}

#pragma mark - controls

- (IBAction)closePlayback:(id)sender
{
    [self.navigationController popViewControllerAnimated:YES];
}

- (IBAction)positionSliderAction:(UISlider *)sender
{
    _mediaPlayer.position = sender.value;
    [self resetIdleTimer];
}

- (void)mediaPlayerTimeChanged:(NSNotification *)aNotification {
    self.positionSlider.value = [_mediaPlayer position];
    self.timeDisplay.title = [[_mediaPlayer remainingTime] stringValue];
}

- (void)mediaPlayerStateChanged:(NSNotification *)aNotification
{
    // TODO
}

- (IBAction)play:(id)sender
{
    if ([_mediaPlayer isPlaying]) {
        [_mediaPlayer pause];
        _playPauseButton.titleLabel.text = @"Pse";
    } else {
        [_mediaPlayer play];
        _playPauseButton.titleLabel.text = @"Play";
    }
}

- (IBAction)forward:(id)sender
{
    [_mediaPlayer mediumJumpForward];
}

- (IBAction)backward:(id)sender
{
    [_mediaPlayer mediumJumpBackward];
}

- (IBAction)switchAudioTrack:(id)sender
{
    _audiotrackActionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"CHOOSE_AUDIO_TRACK", @"audio track selector") delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles: nil];
    NSArray *audioTracks = [_mediaPlayer audioTrackNames];
    NSUInteger count = [audioTracks count];
    for (NSUInteger i = 0; i < count; i++)
        [_audiotrackActionSheet addButtonWithTitle:audioTracks[i]];
    [_audiotrackActionSheet addButtonWithTitle:NSLocalizedString(@"BUTTON_CANCEL", @"cancel button")];
    [_audiotrackActionSheet setCancelButtonIndex:[_audiotrackActionSheet numberOfButtons] - 1];
    [_audiotrackActionSheet showFromRect:[self.audioSwitcherButton frame] inView:self.audioSwitcherButton animated:YES];
}

- (IBAction)switchSubtitleTrack:(id)sender
{
    NSArray *spuTracks = [_mediaPlayer videoSubTitlesNames];
    NSUInteger count = [spuTracks count];
    if (count <= 1)
        return;
    _subtitleActionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"CHOOSE_SUBTITLE_TRACK", @"subtitle track selector") delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles: nil];
    for (NSUInteger i = 0; i < count; i++)
        [_subtitleActionSheet addButtonWithTitle:spuTracks[i]];
    [_subtitleActionSheet addButtonWithTitle:NSLocalizedString(@"BUTTON_CANCEL", @"cancel button")];
    [_subtitleActionSheet setCancelButtonIndex:[_subtitleActionSheet numberOfButtons] - 1];
    [_subtitleActionSheet showFromRect:[self.subtitleSwitcherButton frame] inView:self.subtitleSwitcherButton animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSUInteger arrayIndex = 0;
    NSArray *indexArray;
    NSArray *namesArray;
    if (actionSheet == _subtitleActionSheet) {
        namesArray = _mediaPlayer.videoSubTitlesNames;
        arrayIndex = [namesArray indexOfObject:[actionSheet buttonTitleAtIndex:buttonIndex]];
        if (arrayIndex != NSNotFound) {
            indexArray = _mediaPlayer.videoSubTitlesIndexes;
            _mediaPlayer.currentVideoSubTitleIndex = [indexArray[arrayIndex] intValue];
        }
    } else if (actionSheet == _audiotrackActionSheet) {
        namesArray = _mediaPlayer.audioTrackNames;
        arrayIndex = [namesArray indexOfObject:[actionSheet buttonTitleAtIndex:buttonIndex]];
        if (arrayIndex != NSNotFound) {
            indexArray = _mediaPlayer.audioTrackIndexes;
            _mediaPlayer.currentAudioTrackIndex = [indexArray[arrayIndex] intValue];
        }
    } else if (actionSheet == _aspectRatioActionSheet) {
        if (actionSheet.cancelButtonIndex != buttonIndex) {
            if ([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:@"Default"])
                _mediaPlayer.videoAspectRatio = NULL;
            else
                _mediaPlayer.videoAspectRatio = (char *)[[actionSheet buttonTitleAtIndex:buttonIndex] UTF8String];
        }
    } else if (actionSheet == _cropActionSheet) {
        if (actionSheet.cancelButtonIndex != buttonIndex) {
            if ([[actionSheet buttonTitleAtIndex:buttonIndex] isEqualToString:@"Default"])
                _mediaPlayer.videoCropGeometry = NULL;
            else
                _mediaPlayer.videoCropGeometry = (char *)[[actionSheet buttonTitleAtIndex:buttonIndex] UTF8String];
        }
    }
}

#pragma mark - Video Filter UI

- (IBAction)videoFilterToggle:(id)sender
{
    if (!_playbackViewHidden)
        self.playbackView.hidden = _playbackViewHidden = YES;

    self.videoFilterView.hidden = !_videoFiltersHidden;
    _videoFiltersHidden = self.videoFilterView.hidden;
    self.controllerPanel.hidden = !_videoFiltersHidden;
}

- (IBAction)videoFilterSliderAction:(id)sender
{
    if (sender == self.hueSlider)
        _mediaPlayer.hue = (int)self.hueSlider.value;
    else if (sender == self.contrastSlider)
        _mediaPlayer.contrast = self.contrastSlider.value;
    else if (sender == self.brightnessSlider) {
        if ([self hasExternalDisplay])
            _mediaPlayer.brightness = self.brightnessSlider.value;
        else
            [[UIScreen mainScreen] setBrightness:(self.brightnessSlider.value / 2.)];
    } else if (sender == self.saturationSlider)
        _mediaPlayer.saturation = self.saturationSlider.value;
    else if (sender == self.gammaSlider)
        _mediaPlayer.gamma = self.gammaSlider.value;
    else if (sender == self.resetVideoFilterButton) {
        _mediaPlayer.hue = self.hueSlider.value = 0.;
        _mediaPlayer.contrast = self.contrastSlider.value = 1.;
        _mediaPlayer.brightness = self.brightnessSlider.value = 1.;
        _mediaPlayer.saturation = self.saturationSlider.value = 1.;
        _mediaPlayer.gamma = self.gammaSlider.value = 1.;
    } else
        APLog(@"unknown sender for videoFilterSliderAction");
    [self resetIdleTimer];
}

#pragma mark - playback view
- (IBAction)playbackSpeedSliderAction:(UISlider *)sender
{
    double speed = pow(2, sender.value / 17.);
    float rate = INPUT_RATE_DEFAULT / speed;
    if (_currentPlaybackRate != rate)
        [_mediaPlayer setRate:INPUT_RATE_DEFAULT / rate];
    _currentPlaybackRate = rate;
    [self _updatePlaybackSpeedIndicator];
    [self resetIdleTimer];
}

- (void)_updatePlaybackSpeedIndicator
{
    float f_value = self.playbackSpeedSlider.value;
    double speed =  pow(2, f_value / 17.);
    self.playbackSpeedIndicator.text = [NSString stringWithFormat:@"%.2fx", speed];
}

- (float)_playbackSpeed
{
    float f_rate = _mediaPlayer.rate;

    double value = 17 * log(f_rate) / log(2.);
    float returnValue = (int) ((value > 0) ? value + .5 : value - .5);

    if (returnValue < -34.)
        returnValue = -34.;
    else if (returnValue > 34.)
        returnValue = 34.;

    _currentPlaybackRate = returnValue;
    return returnValue;
}

- (IBAction)videoDimensionAction:(id)sender
{
    if (sender == self.playbackButton) {
        if (!_videoFiltersHidden)
            self.videoFilterButton.hidden = _videoFiltersHidden = YES;

        self.playbackView.hidden = !_playbackViewHidden;
        _playbackViewHidden = self.playbackView.hidden;
        self.controllerPanel.hidden = !_playbackViewHidden;
    } else if (sender == self.aspectRatioButton) {
        NSArray *ratios = @[@"Default", @"1:1", @"4:3", @"16:9", @"16:10", @"2.21:1", @"2:35:1", @"2.39:1", @"5:4"];
        NSUInteger count = [ratios count];

        _aspectRatioActionSheet = [[UIActionSheet alloc] initWithTitle:@"Choose Aspect Ratio" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles: nil];
        for (NSUInteger i = 0; i < count; i++)
            [_aspectRatioActionSheet addButtonWithTitle:ratios[i]];
        [_aspectRatioActionSheet addButtonWithTitle:NSLocalizedString(@"Cancel", @"subtitle track selector")];
        [_aspectRatioActionSheet setCancelButtonIndex:[_aspectRatioActionSheet numberOfButtons] - 1];
        [_aspectRatioActionSheet showFromRect:[self.aspectRatioButton frame] inView:self.aspectRatioButton animated:YES];
    } else if (sender == self.cropButton) {
        NSArray *ratios = @[@"Default", @"16:10", @"16:9", @"1.85:1", @"2.21:1", @"2.35:1", @"2:39:1", @"5:3", @"4:3", @"5:4", @"1:1"];
        NSUInteger count = [ratios count];

        _cropActionSheet = [[UIActionSheet alloc] initWithTitle:@"Choose Aspect Ratio" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles: nil];
        for (NSUInteger i = 0; i < count; i++)
            [_cropActionSheet addButtonWithTitle:ratios[i]];
        [_cropActionSheet addButtonWithTitle:NSLocalizedString(@"Cancel", @"subtitle track selector")];
        [_cropActionSheet setCancelButtonIndex:[_cropActionSheet numberOfButtons] - 1];
        [_cropActionSheet showFromRect:[self.cropButton frame] inView:self.cropButton animated:YES];
    }
}

#pragma mark -

- (void)appWillResign:(NSNotification *)aNotification
{
    self.mediaItem.lastPosition = @([_mediaPlayer position]);
}

#pragma mark - autorotation

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad
           || toInterfaceOrientation != UIInterfaceOrientationMaskPortraitUpsideDown;
}

#pragma mark - External Display

- (BOOL)hasExternalDisplay
{
    return ([[UIScreen screens] count] > 1);
}

- (void)showOnExternalDisplay
{
    UIScreen *screen = [UIScreen screens][1];
    screen.overscanCompensation = UIScreenOverscanCompensationInsetApplicationFrame;

    self.externalWindow = [[UIWindow alloc] initWithFrame:screen.bounds];

    UIViewController *controller = [[VLCExternalDisplayController alloc] init];
    self.externalWindow.rootViewController = controller;
    [controller.view addSubview:_movieView];
    controller.view.frame = screen.bounds;
    _movieView.frame = screen.bounds;

    self.playingExternallyView.hidden = NO;
    self.externalWindow.screen = screen;
    self.externalWindow.hidden = NO;
}

- (void)hideFromExternalDisplay
{
    [self.view addSubview:_movieView];
    [self.view sendSubviewToBack:_movieView];
    _movieView.frame = self.view.frame;

    self.playingExternallyView.hidden = YES;
    self.externalWindow.hidden = YES;
    self.externalWindow = nil;
}

- (void)handleExternalScreenDidConnect:(NSNotification *)notification
{
    [self showOnExternalDisplay];
}

- (void)handleExternalScreenDidDisconnect:(NSNotification *)notification
{
    [self hideFromExternalDisplay];
}

@end
