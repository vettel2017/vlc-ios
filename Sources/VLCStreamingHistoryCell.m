/*****************************************************************************
 * VLCStreamingHistoryCell.m
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2016 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Adam Viaud <mcnight # mcnight.fr>
 *
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

#import "VLCStreamingHistoryCell.h"

@implementation VLCStreamingHistoryCell

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    return (action == @selector(copy:) || action == @selector(renameStream:)) || [super canPerformAction:action withSender:sender];
}

- (void)customizeAppearance {
    self.textLabel.textColor = [UIColor whiteColor];
    self.detailTextLabel.textColor = [UIColor VLCLightTextColor];
}

- (void)renameStream:(id)sender {
    [self.delegate renameStreamFromCell:self];
}

@end
