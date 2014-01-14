//
//  CameraEngine.m
//  Encoder Demo
//
//  Created by Geraint Davies on 19/02/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import "CameraEngine.h"
#import "VideoEncoder.h"
#import "AssetsLibrary/ALAssetsLibrary.h"

#define VideoScreenWidth    640
#define VideoScreenHeight   640

static CameraEngine* theEngine;

@interface CameraEngine  () <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate>
{
    AVCaptureSession* _session;
    AVCaptureVideoPreviewLayer* _preview;
    dispatch_queue_t _captureQueue;
    AVCaptureConnection* _audioConnection;
    AVCaptureConnection* _videoConnection;
    
    VideoEncoder *_encoder;
    BOOL _isCapturing;
    BOOL _isPaused;
    BOOL _discont;
    int _currentFile;
    CMTime _timeOffset;
    CMTime _lastVideo;
    CMTime _lastAudio;
    
    int _cx;
    int _cy;
    int _channels;
    Float64 _samplerate;
}

@property (nonatomic, assign) CMTime frameDuration;
@property (nonatomic, assign) CMTime nextPTS;
@property (nonatomic, strong) NSString *moveFilePath;

@end

@implementation CameraEngine

@synthesize isCapturing = _isCapturing;
@synthesize isPaused = _isPaused;

+ (void) initialize
{
    // test recommended to avoid duplicate init via subclass
    if (self == [CameraEngine class])
    {
        theEngine = [[CameraEngine alloc] init];
        [theEngine startup];
    }
}

+ (CameraEngine*) engine
{
    return theEngine;
}

- (void) startup
{
    if (_session == nil)
    {
        NSLog(@"Starting up server");

        self.nextPTS = kCMTimeZero;
        self.frameDuration = CMTimeMakeWithSeconds(1./24., 90000);
        self.isCapturing = NO;
        self.isPaused = NO;
        _currentFile = 0;
        _discont = NO;
        _captureQueue = dispatch_queue_create("com.capturepause", DISPATCH_QUEUE_SERIAL);
        
        //1.0 初始化数据解析对象
        NSString* filename = [NSString stringWithFormat:@"final_%ld.mp4", (long)[[NSDate date] timeIntervalSince1970]];
        self.moveFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
        NSLog(@"path = %@", self.moveFilePath);
        _encoder = [[VideoEncoder alloc] init];
        [_encoder initWithPath:self.moveFilePath outPutSize:CGSizeMake(VideoScreenWidth, VideoScreenHeight)];
        
        //2.0 初始化session
        _session = [[AVCaptureSession alloc] init];
        [_session beginConfiguration];
        _session.sessionPreset = AVCaptureSessionPreset640x480;
        
        
        //2.1 添加video输入设备
        AVCaptureDevice *videoDevice = [self cameraWithPosition:AVCaptureDevicePositionBack];
        AVCaptureDeviceInput *videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
        NSParameterAssert(videoInput);
        NSParameterAssert([_session canAddInput:videoInput]);
        [_session addInput:videoInput];
        
        //2.2. 添加audio输入设备
        AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
        NSParameterAssert(audioInput);
        NSParameterAssert([_session canAddInput:audioInput]);
        [_session addInput:audioInput];
        
        //2.3. 创建video输出对象
        AVCaptureVideoDataOutput* videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        [videoOutput setSampleBufferDelegate:self queue:_captureQueue];
        videoOutput.videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                     @(kCVPixelFormatType_32BGRA), kCVPixelBufferPixelFormatTypeKey,
                                     nil];
        NSParameterAssert([_session canAddOutput:videoOutput]);
        [_session addOutput:videoOutput];
        _videoConnection = [videoOutput connectionWithMediaType:AVMediaTypeVideo];
        
        //2.4. 创建audio输出对象
        AVCaptureAudioDataOutput* audioOutput = [[AVCaptureAudioDataOutput alloc] init];
        [audioOutput setSampleBufferDelegate:self queue:_captureQueue];
        NSParameterAssert([_session canAddOutput:audioOutput]);
        [_session addOutput:audioOutput];
        _audioConnection = [audioOutput connectionWithMediaType:AVMediaTypeAudio];
        
        //3.0 设置显示层并启动session
        [_session commitConfiguration];
        _preview = [AVCaptureVideoPreviewLayer layerWithSession:_session];
        _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [_session startRunning];
    }
}

- (void) startCapture
{
    @synchronized(self)
    {
        if (!self.isCapturing)
        {
            NSLog(@"starting capture");
            
            // create the encoder once we have the audio params
            self.isPaused = NO;
            _discont = NO;
            _timeOffset = CMTimeMake(0, 0);
            self.isCapturing = YES;
        }
    }
}

- (void) stopCapture
{
    @synchronized(self)
    {
        if (self.isCapturing)
        {
            NSLog(@"stop capture");
            
            [_session stopRunning];
            _session = nil;
            // serialize with audio and video capture
            
            self.isCapturing = NO;
            dispatch_async(_captureQueue, ^{
                [_encoder finishWithCompletionHandler:^{
                    
                }];
            });
        }
    }
}

- (void) pauseCapture
{
    @synchronized(self)
    {
        if (self.isCapturing)
        {
            NSLog(@"Pausing capture");
            self.isPaused = YES;
            _discont = YES;
        }
    }
}

- (void) resumeCapture
{
    @synchronized(self)
    {
        if (self.isPaused)
        {
            NSLog(@"Resuming capture");
            self.isPaused = NO;
        }
    }
}

- (void) reversalCamera {
    @synchronized(self) {
        NSArray *inputs = _session.inputs;
        for ( AVCaptureDeviceInput *input in inputs ) {
            AVCaptureDevice *device = input.device;
            if ([device hasMediaType:AVMediaTypeVideo]) {
                AVCaptureDevicePosition position = device.position;
                AVCaptureDevice *newCamera = nil;
                AVCaptureDeviceInput *newInput = nil;
                
                if (position == AVCaptureDevicePositionFront) {
                    newCamera = [self cameraWithPosition:AVCaptureDevicePositionBack];
                }
                else {
                    newCamera = [self cameraWithPosition:AVCaptureDevicePositionFront];
                }
                newInput = [AVCaptureDeviceInput deviceInputWithDevice:newCamera error:nil];
                
                // beginConfiguration ensures that pending changes are not applied immediately
                [_session beginConfiguration];
                
                [_session removeInput:input];
                [_session addInput:newInput];
                
                // Changes take effect once the outermost commitConfiguration is invoked.
                [_session commitConfiguration];
                break;
            }
        }
    }
}

- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if ( ! self.isCapturing || self.isPaused) {
        NSLog(@"is paused!");
        return;
    }
    
    NSLog(@"sample buffer data is arrived");
    
    if (connection == _videoConnection) {
        NSLog(@"is video");
        
//        CMSampleTimingInfo timingInfo = kCMTimingInfoInvalid;
//        timingInfo.duration = self.frameDuration;
//        timingInfo.presentationTimeStamp = self.nextPTS;
//        CMSampleBufferRef sbufWithNewTiming = NULL;
//        
//        
//        OSStatus err = CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault,
//                                                             sampleBuffer,
//                                                             1,
//                                                             &timingInfo,
//                                                             &sbufWithNewTiming);
//        if (err) {
//            NSLog(@"CMSampleBufferCreateCopyWithNewTiming error");
//            return;
//        }
        
        [_encoder encodeFrame:sampleBuffer isVideo:YES];
        self.nextPTS = CMTimeAdd(self.frameDuration, self.nextPTS);
    }
    else {
        NSLog(@"is audio");
        
        [_encoder encodeFrame:sampleBuffer isVideo:NO];
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
}

- (AVCaptureVideoPreviewLayer*) getPreviewLayer
{
    return _preview;
}

#pragma mark - 私有方法

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition) position
{
    __block AVCaptureDevice *foundDevice = nil;
    
    [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] enumerateObjectsUsingBlock:^(AVCaptureDevice *device, NSUInteger idx, BOOL *stop) {
        
        if (device.position == position)
        {
            foundDevice = device;
            *stop = YES;
        }
        
    }];
    
    return foundDevice;
}

- (void)convertToMp4 {
//    NSString* _mp4Quality = AVAssetExportPresetMediumQuality;
//    
//    // 试图删除原mp4
//    if ([[NSFileManager defaultManager] fileExistsAtPath:self.moveFilePath]) {
//        [[NSFileManager defaultManager] removeItemAtURL:[NSURL URLWithString:self.moveFilePath] error:nil];
//    }
//    
//    // 生成mp4
//    AVURLAsset *avAsset = [AVURLAsset URLAssetWithURL:self.outputMovURL options:nil];
//    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:avAsset];
//    
//    if ([compatiblePresets containsObject:_mp4Quality]) {
//        __block AVAssetExportSession *exportSession = [[AVAssetExportSession alloc]initWithAsset:avAsset
//                                                                                      presetName:_mp4Quality];
//        
//        exportSession.outputURL = self.outputMp4URL;
//        exportSession.outputFileType = AVFileTypeMPEG4;
//        [exportSession exportAsynchronouslyWithCompletionHandler:^{
//            [blockSelf hideHUDLoading];
//            switch ([exportSession status]) {
//                case AVAssetExportSessionStatusFailed:
//                    [blockSelf showResultThenHide:@"转换mp4出错"];
//                    break;
//                case AVAssetExportSessionStatusCancelled:
//                    [blockSelf showResultThenHide:@"转换被取消"];
//                    break;
//                case AVAssetExportSessionStatusCompleted:
//                    [blockSelf performSelectorOnMainThread:@selector(convertFinish) withObject:nil waitUntilDone:NO];
//                    break;
//                default:
//                    break;
//            }
//        }];
//    }
//    else {
//        [self hideHUDLoading];
//        [self showResultThenHide:@"转换mp4出错！"];
//    }
}

// 通过抽样缓存数据创建一个UIImage对象
- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
    // 为媒体数据设置一个CMSampleBuffer的Core Video图像缓存对象
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // 锁定pixel buffer的基地址
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // 得到pixel buffer的基地址
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // 得到pixel buffer的行字节数
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // 得到pixel buffer的宽和高
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // 创建一个依赖于设备的RGB颜色空间
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // 用抽样缓存的数据创建一个位图格式的图形上下文（graphics context）对象
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // 根据这个位图context中的像素数据创建一个Quartz image对象
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // 解锁pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // 释放context和颜色空间
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // 用Quartz image创建一个UIImage对象image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    // 释放Quartz image对象
    CGImageRelease(quartzImage);
    
    return (image);  
}

- (UIImage *) imageFromSampleBuffer1:(CMSampleBufferRef) sampleBuffer
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer,0);
    
    // Get the number of bytes per row for the pixel buffer
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace)
    {
        NSLog(@"CGColorSpaceCreateDeviceRGB failure");
        return nil;
    }
    
    // Get the base address of the pixel buffer
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    // Get the data size for contiguous planes of the pixel buffer.
    size_t bufferSize = CVPixelBufferGetDataSize(imageBuffer);
    
    // Create a Quartz direct-access data provider that uses data we supply
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, baseAddress, bufferSize,
                                                              NULL);
    // Create a bitmap image from data supplied by our data provider
    CGImageRef cgImage = CGImageCreate(width,
                                       height,
                                       8,
                                       32,
                                       bytesPerRow,
                                       colorSpace,
                                       kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little,
                                       provider,
                                       NULL,
                                       true,
                                       kCGRenderingIntentDefault);
    
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
    
    // Create and return an image object representing the specified Quartz image
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    
    return image;
}

@end
