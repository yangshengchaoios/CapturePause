//
//  CapturePauseViewController.m
//  CapturePause
//
//  Created by Geraint Davies on 27/02/2013.
//  Copyright (c) 2013 Geraint Davies. All rights reserved.
//

#import "CapturePauseViewController.h"
#import "CameraEngine.h"

@interface CapturePauseViewController ()

@property (nonatomic, weak) IBOutlet UIButton *controlButton;
@property (nonatomic, weak) IBOutlet UIButton *stopButton;
@property (nonatomic, weak) IBOutlet UIButton *reversalButton;
@property (nonatomic, assign) BOOL isStarted;

@end

@implementation CapturePauseViewController

@synthesize cameraView;

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self startPreview];
    
    self.isStarted = NO;
    [self.controlButton setTitle:@"highlighted" forState:UIControlStateHighlighted];
    [self.controlButton setTitle:@"normal" forState:UIControlStateNormal];
    [self.controlButton addTarget:self action:@selector(startRecording:) forControlEvents:UIControlEventTouchDown];
    [self.controlButton addTarget:self action:@selector(startRecording:) forControlEvents:UIControlEventTouchDragEnter];
    [self.controlButton addTarget:self action:@selector(pauseRecording:) forControlEvents:UIControlEventTouchUpInside];
    [self.controlButton addTarget:self action:@selector(pauseRecording:) forControlEvents:UIControlEventTouchDragExit];
    
    [self.stopButton addTarget:self action:@selector(stopRecording:) forControlEvents:UIControlEventTouchUpInside];
    [self.reversalButton addTarget:self action:@selector(reversalButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
}

- (void) startPreview
{
    AVCaptureVideoPreviewLayer* preview = [[CameraEngine engine] getPreviewLayer];
    [preview removeFromSuperlayer];
    preview.frame = self.cameraView.bounds;
//    [[preview connection] setVideoOrientation:AVCaptureVideoOrientationPortrait];
    
    [self.cameraView.layer addSublayer:preview];
}

- (IBAction)startRecording:(id)sender
{
    if ( ! self.isStarted) {
        self.isStarted = YES;
        [[CameraEngine engine] startCapture];
    }
    else {
        [[CameraEngine engine] resumeCapture];
    }
}

- (IBAction)pauseRecording:(id)sender
{
    [[CameraEngine engine] pauseCapture];
}

- (IBAction)stopRecording:(id)sender
{
    self.isStarted = NO;
    [[CameraEngine engine] stopCapture];
}

- (IBAction)reversalButtonClicked:(id)sender {
    [[CameraEngine engine] reversalCamera];
}

@end
