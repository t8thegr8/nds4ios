//
//  ViewController.m
//  nds4ios
//
//  Created by rock88 on 11/12/2012.
//  Copyright (c) 2012 Homebrew. All rights reserved.
//

#import "AppDelegate.h"

#import "EmuViewController.h"
#import "UIScreen+Widescreen.h"
#import "GLProgram.h"


#import <GLKit/GLKit.h>
#import <OpenGLES/ES2/gl.h>

#include "emu.h"

#define STRINGIZE(x) #x
#define STRINGIZE2(x) STRINGIZE(x)
#define SHADER_STRING(text) @ STRINGIZE2(text)

NSString *const kVertShader = SHADER_STRING
(
    attribute vec4 position;
    attribute vec2 inputTextureCoordinate;
    
    varying highp vec2 texCoord;
                                            
    void main()
    {
        texCoord = inputTextureCoordinate;
        gl_Position = position;
    }
);

NSString *const kFragShader = SHADER_STRING
(
    uniform sampler2D inputImageTexture;
    varying highp vec2 texCoord;
    
    void main()
    {
        highp vec4 color = texture2D(inputImageTexture, texCoord);
        gl_FragColor = color;
    }
);

const float positionVert[] =
{
    -1.0f, 1.0f,
    1.0f, 1.0f,
    -1.0f, -1.0f,
    1.0f, -1.0f
};

const float textureVert[] =
{
    0.0f, 0.0f,
    1.0f, 0.0f,
    0.0f, 1.0f,
    1.0f, 1.0f
};

@interface EmuViewController () <GLKViewDelegate>
{
    int fps;
    
    GLuint texHandle;
    GLint attribPos;
    GLint attribTexCoord;
    GLint texUniform;
    
}

typedef enum : NSInteger {
    RSTButtonPositionTop = 0,
    RSTButtonPositionBottom = 1,
} RSTButtonPosition;

@property (nonatomic,strong) UILabel* fpsLabel;
@property (nonatomic,strong) NSString* documentsPath;
@property (nonatomic,strong) NSString* rom;
@property (nonatomic,strong) NSArray* buttonsArray;
@property (nonatomic,strong) GLProgram* program;
@property (nonatomic,strong) EAGLContext* context;
@property (nonatomic,strong) GLKView* glkView;
@property (nonatomic,assign) BOOL initialize;

@end

@implementation EmuViewController
@synthesize fpsLabel,documentsPath,rom,initialize;
@synthesize program,context,glkView,buttonsArray;

- (id)initWithRom:(NSString*)_rom
{
    self = [super init];
    if (self) {
        self.documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        
        initialize = YES;
        self.rom = [NSString stringWithFormat:@"%@/%@",self.documentsPath,_rom];
    }
    return self;
}

- (void)killCurrentGame
{
    EMU_closeRom();
    [self shutdownGL];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if (initialize == YES)
    {
        EMU_closeRom();
    }
    
    self.view.multipleTouchEnabled = YES;
    
    self.fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(6, 0, 100, 30)];
    self.fpsLabel.backgroundColor = [UIColor clearColor];
    self.fpsLabel.textColor = [UIColor greenColor];
    self.fpsLabel.shadowColor = [UIColor blackColor];
    self.fpsLabel.shadowOffset = CGSizeMake(1.0f, 1.0f);
    self.fpsLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:18];
    [self.view addSubview:self.fpsLabel];
    
    [self addButtons];
    
    [self initRom];
    
    [self performSelector:@selector(emuLoop) withObject:nil];    
}

- (void)viewWillAppear:(BOOL)animated
{
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"shiftPad"])
        [self shiftButtons];
    else
        [self unshiftButtons];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"onScreenControl"] == NO)
        [self hideControls];
    else
        [self showControls];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)viewDidUnload
{
    //[self shutdownGL];
    [super viewDidUnload];
}

- (void)dealloc
{
    [self viewDidUnload];
}

- (void)initRom
{
    initialize = YES;
    EMU_setWorkingDir([self.documentsPath UTF8String]);
    EMU_init();
    EMU_loadRom([self.rom UTF8String]);
    EMU_change3D(1);
    EMU_changeSound(0);
    
    [self initGL];
}

- (void)initGL
{
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    [EAGLContext setCurrentContext:self.context];
    
    CGRect frame = CGRectMake(0, 0, self.view.bounds.size.width, 480.0f); // Temporarily hardcoding 480 to keep aspect ratio the same for all non-iPad iOS Devices
    
    self.glkView = [[GLKView alloc] initWithFrame:frame context:self.context];
    self.glkView.delegate = self;
    [self.view insertSubview:self.glkView atIndex:0];
    
    self.program = [[GLProgram alloc] initWithVertexShaderString:kVertShader fragmentShaderString:kFragShader];
    
    [self.program addAttribute:@"position"];
	[self.program addAttribute:@"inputTextureCoordinate"];
    
    [self.program link];
    
    attribPos = [self.program attributeIndex:@"position"];
    attribTexCoord = [self.program attributeIndex:@"inputTextureCoordinate"];
    
    texUniform = [self.program uniformIndex:@"inputImageTexture"];
    
    glEnableVertexAttribArray(attribPos);
    glEnableVertexAttribArray(attribTexCoord);
    
    float scale = [UIScreen mainScreen].scale;
    CGSize size = CGSizeMake(self.glkView.bounds.size.width * scale, self.glkView.bounds.size.height * scale);
    
    glViewport(0, 0, size.width, size.height);
    
    [self.program use];
    
    glGenTextures(1, &texHandle);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, texHandle);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

- (void)shutdownGL
{
    glDeleteTextures(1, &texHandle);
    self.context = nil;
    self.program = nil;
    [EAGLContext setCurrentContext:nil];
}

- (void)emuLoop
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while (execute) {
            EMU_runCore();
            fps = EMU_runOther();
            EMU_copyMasterBuffer();
            
            [self updateDisplay];
        }
    });
}

- (void)updateDisplay
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.fpsLabel.text = [NSString stringWithFormat:@"FPS: %d",fps];
    });
    
    glBindTexture(GL_TEXTURE_2D, texHandle);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 256, 384, 0, GL_RGBA, GL_UNSIGNED_BYTE, &video.buffer);
    
    [self.glkView display];
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, texHandle);
    glUniform1i(texUniform, 1);
    
    glVertexAttribPointer(attribPos, 2, GL_FLOAT, 0, 0, (const GLfloat*)&positionVert);
    glVertexAttribPointer(attribTexCoord, 2, GL_FLOAT, 0, 0, (const GLfloat*)&textureVert);
    
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

- (void)showControls
{
    for (UIControl *button in buttonsArray) {
        button.alpha = 1;
    }
}

- (void)hideControls
{
    for (UIControl *button in buttonsArray) {
        button.alpha = .1;
    }
}

- (UIButton*)buttonWithId:(BUTTON_ID)_buttonId atCenter:(CGPoint)center
{
    NSArray* array = @[@"Right",@"Left",@"Down",@"Up",@"Select",@"Start",@"B",@"A",@"Y",@"X",@"L",@"R"];
    
    UIButton* button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [button setTitle:array[_buttonId] forState:UIControlStateNormal];
    
    if (_buttonId == BUTTON_START || _buttonId == BUTTON_SELECT) {
        button.frame = CGRectMake(0, 0, 50, 25);
    } else {
        button.frame = CGRectMake(0, 0, 40, 40);
    }
    button.center = center;
    
    button.titleLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:10.0f];
    button.alpha = 0.6f;
    button.tag = _buttonId;
    
    [button addTarget:self action:@selector(onButtonUp:) forControlEvents:UIControlEventTouchUpInside];
    [button addTarget:self action:@selector(onButtonDown:) forControlEvents:UIControlEventTouchDown];
    
    return button;
}

- (void)addButtons
{
    buttonDPad = [[ButtonPad alloc] initWithFrame:CGRectMake(0, 112, 120, 120)];
    buttonDPad.image = [UIImage imageNamed:@"DPad"];
    [buttonDPad addTarget:self action:@selector(onDPad:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:buttonDPad];
    
    buttonABXYPad = [[ButtonPad alloc] initWithFrame:CGRectMake(200, 112, 120, 120)];
    buttonABXYPad.image = [UIImage imageNamed:@"ABXYPad"];
    [buttonABXYPad addTarget:self action:@selector(onABXY:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:buttonABXYPad];
    
    buttonSelect = [self buttonWithId:BUTTON_SELECT atCenter:CGPointMake(132, 228)];
    [self.view addSubview:buttonSelect];
    
    buttonStart = [self buttonWithId:BUTTON_START atCenter:CGPointMake(186, 228)];
    [self.view addSubview:buttonStart];
    
    buttonExit = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [buttonExit setTitle:@"Close" forState:UIControlStateNormal];
    buttonExit.frame = CGRectMake(0, 0, 50, 25);
    buttonExit.center = CGPointMake(160, 20);
    [buttonExit addTarget:self action:@selector(buttonExitDown:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:buttonExit];
    
    buttonLT = [self buttonWithId:BUTTON_L atCenter:CGPointMake(20, 70)];
    [self.view addSubview:buttonLT];
    
    buttonRT = [self buttonWithId:BUTTON_R atCenter:CGPointMake(self.view.frame.size.width - 20, 70)];
    [self.view addSubview:buttonRT];
    
    self.buttonsArray = @[buttonDPad,
                          buttonABXYPad,
                          buttonSelect,buttonStart, buttonRT, buttonLT];
}

- (void)onButtonUp:(UIControl*)sender
{
    EMU_buttonUp((BUTTON_ID)sender.tag);
}

- (void)onButtonDown:(UIControl*)sender
{
    EMU_buttonDown((BUTTON_ID)sender.tag);
}

- (void)onDPad:(ButtonPad*)sender
{
    UIControlState state = sender.state;
    EMU_setDPad(state & PadStateUp, state & PadStateDown, state & PadStateLeft, state & PadStateRight);
}

- (void)onABXY:(ButtonPad *)sender
{
    UIControlState state = sender.state;
    EMU_setABXY(state & PadStateRight, state & PadStateDown, state & PadStateUp, state & PadStateLeft);
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch* touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.view];
    
    if (point.y < 240.0f) return;
    
    point.x /= 1.33f;
    point.y -= 240.0f;
    point.y /= 1.33f;
    
    EMU_touchScreenTouch(point.x, point.y);
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch* touch = [touches anyObject];
    CGPoint point = [touch locationInView:self.view];
    
    if (point.y < 240) return;
    
    point.x /= 1.33;
    point.y -= 240;
    point.y /= 1.33;
    
    EMU_touchScreenTouch(point.x, point.y);
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    EMU_touchScreenRelease();
}

- (void)unshiftButtons
{
    buttonSelect.center = CGPointMake(buttonSelect.center.x, 228);
    buttonStart.center = CGPointMake(buttonStart.center.x, 228);
    buttonRT.center = CGPointMake(buttonRT.center.x, 70);
    buttonLT.center = CGPointMake(buttonLT.center.x, 70);
    buttonDPad.center = CGPointMake(buttonDPad.center.x, 112+60);
    buttonABXYPad.center = CGPointMake(buttonABXYPad.center.x, 112+60);
}

- (void)shiftButtons
{
    BOOL isWidescreen = [[UIScreen mainScreen] isWidescreen];
    for (UIControl *button in buttonsArray) {
        if (button.center.y < 240.0f) {
            button.center = CGPointMake(button.center.x, button.center.y + 240.0f + (88.0f * isWidescreen));
        } else {
            button.center = CGPointMake(button.center.x, button.center.y - 240.0f - (88.0f * isWidescreen));
        }
    }
}

- (void)buttonExitDown:(id)sender
{
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Background or Kill?\nBackgrounding keeps the current game alive for later, whereas killing it will completely close it." delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:@"Kill" otherButtonTitles:@"Background", nil];
    [sheet showInView:self.view];
}

#pragma mark UIActionSheet delegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == 0)
    {
        [self killCurrentGame];
        [[AppDelegate sharedInstance] killVC:self];
        NSLog(@"killed");
        [self dismissViewControllerAnimated:YES completion:nil];
    } else if (buttonIndex == 1) {
        NSLog(@"backgrounded");
        [self dismissViewControllerAnimated:YES completion:nil];
    }
    
}
@end

