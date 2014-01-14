//
//  VideoEncoder.m
//  Encoder Demo
//
//  Created by Geraint Davies on 14/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import "VideoEncoder.h"

@implementation VideoEncoder

- (void) initWithPath:(NSString*)path outPutSize:(CGSize )size {
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    NSURL* url = [NSURL fileURLWithPath:path];
    
    //文件输出对象
    _mediaWriter = [AVAssetWriter assetWriterWithURL:url fileType:AVFileTypeQuickTimeMovie error:nil];
    
    //设置video输出对象
    NSDictionary *videoCompress = @{AVVideoAverageBitRateKey: @(512.0 * 1024.0)};
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                   AVVideoCodecH264, AVVideoCodecKey,
                                   [NSNumber numberWithInt:size.width], AVVideoWidthKey,
                                   [NSNumber numberWithInt:size.height], AVVideoHeightKey,
                                   AVVideoScalingModeResizeAspectFill, AVVideoScalingModeKey,
                                   videoCompress, AVVideoCompressionPropertiesKey,
                                   nil];
    _videoWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    NSParameterAssert(_videoWriterInput);
    _videoWriterInput.expectsMediaDataInRealTime = YES;
    //设置输出adaptor
    NSDictionary *sourcePixelBufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                                 @(kCVPixelFormatType_32ARGB),kCVPixelBufferPixelFormatTypeKey,
                                                 nil];
    _adaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:_videoWriterInput
                                                                                sourcePixelBufferAttributes:sourcePixelBufferAttributes];
    NSParameterAssert([_mediaWriter canAddInput:_videoWriterInput]);
    
    //设置audio输出对象
    AudioChannelLayout acl;
    bzero(&acl, sizeof(acl));
    acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
    NSDictionary *audioSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @(kAudioFormatMPEG4AAC), AVFormatIDKey,
                                   @(64000), AVEncoderBitRateKey,
                                   @(44100), AVSampleRateKey,
                                   @(1), AVNumberOfChannelsKey,
                                   [NSData dataWithBytes:&acl length:sizeof(acl)], AVChannelLayoutKey,
                                   nil];
    _audioWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioSettings];
    NSParameterAssert(_audioWriterInput);
    _audioWriterInput.expectsMediaDataInRealTime = YES;
    NSParameterAssert([_mediaWriter canAddInput:_audioWriterInput]);
    
    //将video和audio两个输入对象加入文件输出对象
    [_mediaWriter addInput:_videoWriterInput];
    [_mediaWriter addInput:_audioWriterInput];
}

- (void) finishWithCompletionHandler:(void (^)(void))handler
{
    [_videoWriterInput markAsFinished];
    [_audioWriterInput markAsFinished];
    [_mediaWriter finishWritingWithCompletionHandler: handler];
}

static CGFloat DegreesToRadians(CGFloat degrees) {return degrees * M_PI / 180;};

- (BOOL) encodeFrame:(CMSampleBufferRef) sampleBuffer isVideo:(BOOL)bVideo
{
    if (CMSampleBufferDataIsReady(sampleBuffer))
    {
        if (_mediaWriter.status == AVAssetWriterStatusUnknown)
        {
            CGFloat rotationDegrees;
            switch ([[UIDevice currentDevice] orientation]) {
                case UIDeviceOrientationPortraitUpsideDown:
                    rotationDegrees = -90.;
                    break;
                case UIDeviceOrientationLandscapeLeft: // no rotation
                    rotationDegrees = 0.;
                    break;
                case UIDeviceOrientationLandscapeRight:
                    rotationDegrees = 180.;
                    break;
                case UIDeviceOrientationPortrait:
                case UIDeviceOrientationUnknown:
                case UIDeviceOrientationFaceUp:
                case UIDeviceOrientationFaceDown:
                default:
                    rotationDegrees = 90.;
                    break;
            }
            CGFloat rotationRadians = DegreesToRadians(rotationDegrees);
            [_videoWriterInput setTransform:CGAffineTransformMakeRotation(rotationRadians)];
            
            
            CMTime startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            [_mediaWriter startWriting];
            [_mediaWriter startSessionAtSourceTime:startTime];
        }
        if (_mediaWriter.status == AVAssetWriterStatusFailed)
        {
            NSLog(@"writer error %@", _mediaWriter.error.localizedDescription);
            return NO;
        }
        if (bVideo)
        {
            if (_videoWriterInput.readyForMoreMediaData)
            {
                [_videoWriterInput appendSampleBuffer:sampleBuffer];
                return YES;
            }
        }
        else
        {
            if (_audioWriterInput.readyForMoreMediaData)
            {
                [_audioWriterInput appendSampleBuffer:sampleBuffer];
                return YES;
            }
        }
    }
    return NO;
}

@end
