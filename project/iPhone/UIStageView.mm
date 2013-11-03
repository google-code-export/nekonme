//
//  UIStageView.mm
//  Blank
//
//  Created by Hugh on 12/01/10.
//  Copyright __MyCompanyName__ 2010. All rights reserved.
//


#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreMotion/CMMotionManager.h>

#include <Display.h>
#include <Surface.h>
#include <KeyCodes.h>
#include <Utils.h>

  //https://gist.github.com/Jaybles/1323251#comment-791121
#include "UIDeviceHardware.h"

#import <OpenGLES/ES1/gl.h>
#import <OpenGLES/ES1/glext.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

using namespace nme;

void EnableKeyboard(bool inEnable);
extern "C" void nme_app_set_active(bool inActive);

namespace nme { int gFixedOrientation = -1; }

// viewWillDisappear

#ifndef IPHONESIM
CMMotionManager *sgCmManager = 0;
#endif
bool sgHasAccelerometer = false;



// This class wraps the CAEAGLLayer from CoreAnimation into a convenient UIView subclass.
// The view content is basically an EAGL surface you render your OpenGL scene into.
// Note that setting the view non-opaque will only work if the EAGL surface has an alpha channel.
@interface UIStageView : UIView<UITextFieldDelegate>
{    
@private
   BOOL animating;
   BOOL displayLinkSupported;
   id displayLink;
   NSInteger animationFrameInterval;
   NSTimer *animationTimer;
   int    mPrimaryEvent;
@public
   class IOSStage *mStage;
   UITextField *mTextField;
   BOOL mKeyboardEnabled;
   bool   mMultiTouch;
   int    mPrimaryTouchHash;
}


@property (readonly, nonatomic, getter=isAnimating) BOOL animating;
@property (nonatomic) NSInteger animationFrameInterval;

- (void) myInit;
- (void) drawView:(id)sender;
- (void) onPoll:(id)sender;
- (void) enableKeyboard:(bool)withEnable;
- (void) enableMultitouch:(bool)withEnable;
- (BOOL)canBecomeFirstResponder;
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void) startAnimation;
- (void) stopAnimation;

@end

// Global instance ...
UIStageView *sgNMEView = nil;

static FrameCreationCallback sOnFrame = nil;
static bool sgAllowShaders = false;
static bool sgHasDepthBuffer = true;
static bool sgHasStencilBuffer = true;
static bool sgEnableMSAA2 = true;
static bool sgEnableMSAA4 = true;




// --- Stage Implementaton ------------------------------------------------------
// There is a single instance of the stage
class IOSStage : public nme::Stage
{
public:

   int mRenderBuffer;
   bool multisampling;
   bool multisamplingEnabled;

   IOSStage(CALayer *inLayer,bool inInitRef) : nme::Stage(inInitRef)
   {
      defaultFramebuffer = 0;
      colorRenderbuffer = 0;
      depthStencilBuffer = 0;
      mHardwareContext = 0;
      mHardwareSurface = 0;
      mLayer = inLayer;
      mDPIScale = 1.0;
      mOGLContext = 0;
      mRenderBuffer = 0;

      NSString* platform = [UIDeviceHardware platformString];
      //printf("Detected hardware: %s\n", [platform UTF8String]);
      
      //todo ; rather expose this hardware value as a function
      //and they can disable AA selectively on devices themselves 
      //rather than hardcoding it here.
      multisampling = sgEnableMSAA2 || sgEnableMSAA4;
      
      
      if (sgAllowShaders)
      {
         mOGLContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
      }
      else
      {
         mOGLContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES1];
      }
      
      if (!mOGLContext || ![EAGLContext setCurrentContext:mOGLContext])
      {
         throw "Could not initilize OpenGL";
      }
 
      CreateOGLFramebuffer();
   
      #ifndef OBJC_ARC
      mHardwareContext = HardwareContext::CreateOpenGL(inLayer, mOGLContext, sgAllowShaders);
      #else
      mHardwareContext = HardwareContext::CreateOpenGL((__bridge void *)inLayer, (__bridge void *)mOGLContext, sgAllowShaders);
      #endif
      mHardwareContext->IncRef();
      mHardwareContext->SetWindowSize(backingWidth, backingHeight);
      mHardwareSurface = new HardwareSurface(mHardwareContext);
      mHardwareSurface->IncRef();
   }

   double getDPIScale() { return mDPIScale; }


   ~IOSStage()
   {
      if (mOGLContext)
      {
         if (mHardwareSurface)
            mHardwareSurface->DecRef();
         if (mHardwareContext)
            mHardwareContext->DecRef();
         // Tear down GL
         if (defaultFramebuffer)
         {
            if (sgAllowShaders)
            {
               glDeleteFramebuffers(1, &defaultFramebuffer);
            }
            else
            {
               glDeleteFramebuffersOES(1, &defaultFramebuffer);
            }
            defaultFramebuffer = 0;
         }

         if (colorRenderbuffer)
         {
            if (sgAllowShaders)
            {
               glDeleteRenderbuffers(1, &colorRenderbuffer);
            }
            else
            {
               glDeleteRenderbuffersOES(1, &colorRenderbuffer);
            }
            colorRenderbuffer = 0;
         }
   
         if (depthStencilBuffer)
         {
            if (sgAllowShaders)
            {
               glDeleteRenderbuffers(1, &depthStencilBuffer);
            }
            else
            {
               glDeleteRenderbuffersOES(1, &depthStencilBuffer);
            }
            depthStencilBuffer = 0;
         }
  
   
         // Tear down context
         if ([EAGLContext currentContext] == mOGLContext)
            [EAGLContext setCurrentContext:nil];

         #ifndef OBJC_ARC
         [mOGLContext release];
         #endif
      }
   }

   bool getMultitouchSupported() { return true; }

   void setMultitouchActive(bool inActive)
   {
      [ sgNMEView enableMultitouch:inActive ];

   }
   bool getMultitouchActive()
   {
      return sgNMEView->mMultiTouch;
   }

   bool isOpenGL() const { return mOGLContext; }

   /*
   void RenderState()
   {
      if ( [sgNMEView isAnimating] )
         nme::Stage::RenderStage();
   }
   */
   
   void CreateOGLFramebuffer()
   {
      // Create default framebuffer object.
      // The backing will be allocated for the current layer in -resizeFromLayer
      if (sgAllowShaders)
      {
         glGenFramebuffers(1, &defaultFramebuffer);
         glGenRenderbuffers(1, &colorRenderbuffer);
         glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
         glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
         
         [mOGLContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer*)mLayer];
         glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorRenderbuffer);
         
         //fetch the values of size first
         glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
         glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
         
         //Create the depth / stencil buffers
         if (sgHasDepthBuffer && !sgHasStencilBuffer)
         {
            //printf("UIStageView :: Creating Depth buffer. \n");
            //Create just the depth buffer
            glGenRenderbuffers(1, &depthStencilBuffer);
            glBindRenderbuffer(GL_RENDERBUFFER, depthStencilBuffer);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, backingWidth, backingHeight);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthStencilBuffer);
         }
         else if (sgHasDepthBuffer && sgHasStencilBuffer)
         {
            //printf("UIStageView :: Creating Depth buffers. \n");
            //printf("UIStageView :: Creating Stencil buffers. \n");
            
            //Create the depth/stencil buffer combo
            glGenRenderbuffers(1, &depthStencilBuffer);
            glBindRenderbuffer(GL_RENDERBUFFER, depthStencilBuffer);
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8_OES, backingWidth, backingHeight);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthStencilBuffer);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, GL_RENDERBUFFER, depthStencilBuffer);    
         }
         else
         {
            //printf("UIStageView :: No depth/stencil buffer requested. \n");
         }
         
         //printf("Create OGL window %dx%d\n", backingWidth, backingHeight);
         
         // [ddc]
         // code taken from:
         // http://www.gandogames.com/2010/07/tutorial-using-anti-aliasing-msaa-in-the-iphone/
         // http://is.gd/oHLipb
         // https://devforums.apple.com/thread/45850
         // Generate and bind our MSAA Frame and Render buffers
         if (multisampling)
         {
            glGenFramebuffers(1, &msaaFramebuffer);
            glBindFramebuffer(GL_FRAMEBUFFER, msaaFramebuffer);
            glGenRenderbuffers(1, &msaaRenderBuffer);
            glBindRenderbuffer(GL_RENDERBUFFER, msaaRenderBuffer);
            
            glRenderbufferStorageMultisampleAPPLE(GL_RENDERBUFFER, (sgEnableMSAA4 ? 4 : 2) , GL_RGB5_A1, backingWidth, backingHeight);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, msaaRenderBuffer);
            glGenRenderbuffers(1, &msaaDepthBuffer);
            
            multisamplingEnabled = true;
            
         }
         else
         {
            multisamplingEnabled = false;
         }
         
         int framebufferStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);
         
         if (framebufferStatus != GL_FRAMEBUFFER_COMPLETE)
         {
            NSLog(@"Failed to make complete framebuffer object %x",
            glCheckFramebufferStatus(GL_FRAMEBUFFER));
            throw "OpenGL resize failed";
         }
      }
      else
      {
         glGenFramebuffersOES(1, &defaultFramebuffer);
         glGenRenderbuffersOES(1, &colorRenderbuffer);
         glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
         glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
         
         [mOGLContext renderbufferStorage:GL_RENDERBUFFER_OES fromDrawable:(CAEAGLLayer*)mLayer];
         
         glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, colorRenderbuffer);
         
         glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_WIDTH_OES, &backingWidth);
         glGetRenderbufferParameterivOES(GL_RENDERBUFFER_OES, GL_RENDERBUFFER_HEIGHT_OES, &backingHeight);
         
         if (sgHasDepthBuffer && !sgHasStencilBuffer)
         {
            //Create just the depth buffer
            glGenRenderbuffersOES(1, &depthStencilBuffer);
            glBindRenderbufferOES(GL_RENDERBUFFER, depthStencilBuffer);
            glRenderbufferStorageOES(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, backingWidth, backingHeight);
            glFramebufferRenderbufferOES(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depthStencilBuffer);
            
         }
         else if (sgHasDepthBuffer && sgHasStencilBuffer)
         {
            //Create the depth/stencil buffer combo
            glGenRenderbuffersOES(1, &depthStencilBuffer);
            glBindRenderbufferOES(GL_RENDERBUFFER_OES, depthStencilBuffer);
            glRenderbufferStorageOES(GL_RENDERBUFFER_OES, GL_DEPTH24_STENCIL8_OES, backingWidth, backingHeight);
            glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_DEPTH_ATTACHMENT_OES, GL_RENDERBUFFER, depthStencilBuffer);
            glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_STENCIL_ATTACHMENT_OES, GL_RENDERBUFFER, depthStencilBuffer);          
         }
         
         //printf("Create OGL window %dx%d\n", backingWidth, backingHeight);
         
         // [ddc]
         // code taken from:
         // http://www.gandogames.com/2010/07/tutorial-using-anti-aliasing-msaa-in-the-iphone/
         // http://is.gd/oHLipb
         // https://devforums.apple.com/thread/45850
         // Generate and bind our MSAA Frame and Render buffers
         if (multisampling)
         {
            glGenFramebuffersOES(1, &msaaFramebuffer);
            glBindFramebufferOES(GL_FRAMEBUFFER_OES, msaaFramebuffer);
            glGenRenderbuffersOES(1, &msaaRenderBuffer);
            glBindRenderbufferOES(GL_RENDERBUFFER_OES, msaaRenderBuffer);
            
            glRenderbufferStorageMultisampleAPPLE(GL_RENDERBUFFER_OES, (sgEnableMSAA4 ? 4 : 2) , GL_RGB5_A1_OES, backingWidth, backingHeight);
            glFramebufferRenderbufferOES(GL_FRAMEBUFFER_OES, GL_COLOR_ATTACHMENT0_OES, GL_RENDERBUFFER_OES, msaaRenderBuffer);
            glGenRenderbuffersOES(1, &msaaDepthBuffer);
            
            multisamplingEnabled = true;
         }
         else
         {
            multisamplingEnabled = false;
         }
         
         int framebufferStatus = glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES);
         
         if (framebufferStatus != GL_FRAMEBUFFER_COMPLETE_OES)
         {
            NSLog(@"Failed to make complete framebuffer object %x",
            glCheckFramebufferStatusOES(GL_FRAMEBUFFER_OES));
            throw "OpenGL resize failed";
         }
      }
   }
   
   
   void DestroyOGLFramebuffer()
   {
      if (defaultFramebuffer)
      {
         if (sgAllowShaders)
         {
            glDeleteFramebuffers(1, &defaultFramebuffer);
         }
         else
         {
            glDeleteFramebuffersOES(1, &defaultFramebuffer);
         }
      }
      defaultFramebuffer = 0;
      if (colorRenderbuffer)
      {
         if (sgAllowShaders)
         {
            glDeleteRenderbuffers(1, &colorRenderbuffer);
         }
         else
         {
            glDeleteRenderbuffersOES(1, &colorRenderbuffer);
         }
      }
      defaultFramebuffer = 0;
   }

   void OnOGLResize(CAEAGLLayer *inLayer)
   {   
      // Recreate frame buffers ..
      //printf("Resize, set ogl %p : %dx%d\n", mOGLContext, backingWidth, backingHeight);
      [EAGLContext setCurrentContext:mOGLContext];
      DestroyOGLFramebuffer();
      CreateOGLFramebuffer();

      mHardwareContext->SetWindowSize(backingWidth,backingHeight);

      //printf("OnOGLResize %dx%d\n", backingWidth, backingHeight);
      Event evt(etResize);
      evt.x = backingWidth;
      evt.y = backingHeight;
      HandleEvent(evt);

   }
   
   void OnRedraw()
   {
      Event evt(etRedraw);
      HandleEvent(evt);
   }

   void OnPoll()
   {
      bool multisamplingEnabledNow = (GetAA() != 1);
      
      if (multisampling && multisamplingEnabled != multisamplingEnabledNow)
      {
         multisamplingEnabled = multisamplingEnabledNow;
         if (multisamplingEnabled)
         {
            if (sgAllowShaders)
            {
               glBindFramebuffer(GL_FRAMEBUFFER, msaaFramebuffer);
               glBindRenderbuffer(GL_RENDERBUFFER, msaaRenderBuffer);
            }
            else
            {
               glBindFramebufferOES(GL_FRAMEBUFFER_OES, msaaFramebuffer);
               glBindRenderbufferOES(GL_RENDERBUFFER_OES, msaaRenderBuffer);
            }
         }
         else
         {
            if (sgAllowShaders)
            {
               glBindFramebuffer(GL_FRAMEBUFFER, defaultFramebuffer);
               glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
            }
            else
            {
               glBindFramebufferOES(GL_FRAMEBUFFER_OES, defaultFramebuffer);
               glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
            }
         }
      }
      
      if (multisampling && multisamplingEnabled)
      {
         if (sgAllowShaders)
         {
            glBindFramebuffer(GL_FRAMEBUFFER, msaaFramebuffer);  
         }
         else
         {
            glBindFramebufferOES(GL_FRAMEBUFFER_OES, msaaFramebuffer);
         }
      }
    
      Event evt(etPoll);
      HandleEvent(evt);
   }

   void OnEvent(Event &inEvt)
   {
      HandleEvent(inEvt);
   }

   void OnMouseEvent(Event &inEvt)
   {
      inEvt.x *= mDPIScale;
      inEvt.y *= mDPIScale;
      HandleEvent(inEvt);
   }

   void Flip()
   {
      if (multisampling && multisamplingEnabled)
      {
         // [ddc] code taken from
         // http://www.gandogames.com/2010/07/tutorial-using-anti-aliasing-msaa-in-the-iphone/
         // http://is.gd/oHLipb
         // https://devforums.apple.com/thread/45850
         //GLenum attachments[] = {GL_DEPTH_ATTACHMENT_OES};
         //glDiscardFramebufferEXT(GL_READ_FRAMEBUFFER_APPLE, 1, attachments);
         
         if (sgAllowShaders)
         {
            const GLenum discards[] = {GL_DEPTH_ATTACHMENT,GL_COLOR_ATTACHMENT0};
            glDiscardFramebufferEXT(GL_READ_FRAMEBUFFER_APPLE, 2, discards);
         }
         else
         {
            const GLenum discards[] = {GL_DEPTH_ATTACHMENT_OES,GL_COLOR_ATTACHMENT0_OES};
            glDiscardFramebufferEXT(GL_READ_FRAMEBUFFER_APPLE, 2, discards);
         }
         
         //Bind both MSAA and View FrameBuffers.
         if (sgAllowShaders)
         {
            glBindFramebuffer(GL_READ_FRAMEBUFFER_APPLE, msaaFramebuffer);
            glBindFramebuffer(GL_DRAW_FRAMEBUFFER_APPLE, defaultFramebuffer);
         }
         else
         {
            glBindFramebufferOES(GL_READ_FRAMEBUFFER_APPLE, msaaFramebuffer);
            glBindFramebufferOES(GL_DRAW_FRAMEBUFFER_APPLE, defaultFramebuffer);
         }
         
         // Call a resolve to combine both buffers
         glResolveMultisampleFramebufferAPPLE();
         // Present final image to screen
      }
      
      if (sgAllowShaders)
      {
         glBindRenderbuffer(GL_RENDERBUFFER, colorRenderbuffer);
         [mOGLContext presentRenderbuffer:GL_RENDERBUFFER];
      }
      else
      {
         glBindRenderbufferOES(GL_RENDERBUFFER_OES, colorRenderbuffer);
         [mOGLContext presentRenderbuffer:GL_RENDERBUFFER_OES];
      }
   }

   void GetMouse()
   {
      // TODO
   }

   
   Surface *GetPrimarySurface()
   {
      return mHardwareSurface;
   }

   void SetCursor(nme::Cursor)
   {
      // No cursors on iPhone !
   }

   void EnablePopupKeyboard(bool inEnable)
   {
      ::EnableKeyboard(inEnable);
   }



  // --- IRenderTarget Interface ------------------------------------------
   int Width() { return backingWidth; }
   int Height() { return backingHeight; }

   //double getStageWidth() { return backingWidth; }
   //double getStageHeight() { return backingHeight; }



   EventHandler mHandler;
   void *mHandlerData;


   EAGLContext *mOGLContext;
   CALayer *mLayer;
   HardwareSurface *mHardwareSurface;
   HardwareContext *mHardwareContext;


   // The pixel dimensions of the CAEAGLLayer
   GLint backingWidth;
   GLint backingHeight;
   double mDPIScale;
   
   // The OpenGL names for the framebuffer and renderbuffer used to render to this view
   GLuint defaultFramebuffer, colorRenderbuffer, depthStencilBuffer;

   //[ddc] antialiasing code taken from:
   // http://www.gandogames.com/2010/07/tutorial-using-anti-aliasing-msaa-in-the-iphone/
   // http://is.gd/oHLipb
   // https://devforums.apple.com/thread/45850
   // Buffer definitions for the MSAA
   GLuint msaaFramebuffer, msaaRenderBuffer, msaaDepthBuffer;

};





// --- UIStageView -------------------------------------------------------------------

static NSString *sgDisplayLinkMode = NSRunLoopCommonModes;
@implementation UIStageView

@synthesize animating;
@dynamic animationFrameInterval;

// You must implement this method
+ (Class) layerClass
{
  return [CAEAGLLayer class];
}

//The GL view is stored in the nib file. When it's unarchived it's sent -initWithCoder:

- (id) initWithCoder:(NSCoder*)coder
{    
   if ((self = [super initWithCoder:coder]))
   {
      sgNMEView = self;
      [self myInit];
      return self;
   }
   return nil;
}

// For when we init programatically...
- (id) initWithFrame:(CGRect)frame
{    
   if ((self = [super initWithFrame:frame]))
   {
      sgNMEView = self;
      self.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                              UIViewAutoresizingFlexibleHeight;
      [self myInit];
      return self;
   }
   return nil;
}


- (void) myInit
{
      // Get the layer
      CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;

      eaglLayer.opaque = TRUE;
      eaglLayer.drawableProperties = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSNumber numberWithBool:FALSE], kEAGLDrawablePropertyRetainedBacking,
                                      kEAGLColorFormatRGBA8, kEAGLDrawablePropertyColorFormat,
                                      nil];

      mStage = new IOSStage(self.layer,true);

      // Set scaling to ensure 1:1 pixels ...
      if([[UIScreen mainScreen] respondsToSelector: NSSelectorFromString(@"scale")])
      {
         if([self respondsToSelector: NSSelectorFromString(@"contentScaleFactor")])
         {
            mStage->mDPIScale = [[UIScreen mainScreen] scale];
            self.contentScaleFactor = mStage->mDPIScale;
         }
      }

  
      displayLinkSupported = FALSE;
      animationFrameInterval = 1;
      animationTimer = nil;
      mTextField = nil;
      mKeyboardEnabled = NO;
      
      mMultiTouch = false;
      mPrimaryTouchHash = 0;


      animating = true;
      displayLink = [NSClassFromString(@"CADisplayLink") displayLinkWithTarget:self selector:@selector(mainLoop:)];
      [displayLink setFrameInterval:animationFrameInterval];
      [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:sgDisplayLinkMode];

      #ifndef IPHONESIM
      if (!sgCmManager)
      {
         sgCmManager = [[CMMotionManager alloc]init];
         if ([sgCmManager isAccelerometerAvailable])
         {
           sgCmManager.accelerometerUpdateInterval = 0.033;
           [sgCmManager startAccelerometerUpdates];
           sgHasAccelerometer = true;
         }
      }
      #endif
}


- (void) startAnimation
{
   if (!animating)
   {
      [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:sgDisplayLinkMode];
      animating = true;
   }
}

- (void) stopAnimation
{
   if (animating)
   {
      [displayLink removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:sgDisplayLinkMode];
      animating = false;
   }
}

- (void) mainLoop:(id) sender
{
   if (animating)
      [self onPoll:sender];
}

- (void)didMoveToWindow
{
   nme_app_set_active(self.window!=nil);
}

- (BOOL)canBecomeFirstResponder { return YES; }


/* UITextFieldDelegate method.  Invoked when user types something. */

- (BOOL)textField:(UITextField *)_textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {

   if ([string length] == 0)
   {
      /* SDL hack to detect delete */
      Event key_down(etKeyDown);
      key_down.code = keyBACKSPACE;
      key_down.value = keyBACKSPACE;
      mStage->OnEvent(key_down);

      Event key_up(etKeyUp);
      key_up.code = keyBACKSPACE;
      key_up.value = keyBACKSPACE;
      mStage->OnEvent(key_up);
   }
   else
   {
      /* go through all the characters in the string we've been sent
         and convert them to key presses */
      for(int i=0; i<[string length]; i++)
      {
         unichar c = [string characterAtIndex: i];

         Event key_down(etKeyDown);
         key_down.code = c;
         key_down.value = c;
         mStage->OnEvent(key_down);
         
         Event key_up(etKeyUp);
         key_up.code = c;
         key_up.value = c;
         mStage->OnEvent(key_up);
      }
   }

   return NO; /* don't allow the edit! (keep placeholder text there) */
}

/* Terminates the editing session */
- (BOOL)textFieldShouldReturn:(UITextField*)_textField {
   if (mStage->FinishEditOnEnter())
   {
      mStage->SetFocusObject(0);
      [self enableKeyboard:NO];
      return YES;
   }

   // Fake a return character...

   Event key_down(etKeyDown);
   key_down.value = keyENTER;
   key_down.code = keyENTER;
   mStage->OnEvent(key_down);

   Event key_up(etKeyUp);
   key_up.value = keyENTER;
   key_up.code = keyENTER;
   mStage->OnEvent(key_up);
 
   return NO;
}



- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
   NSArray *touchArr = [touches allObjects];
   NSInteger touchCnt = [touchArr count];

   for(int i=0;i<touchCnt;i++)
   {
      UITouch *aTouch = [touchArr objectAtIndex:i];

      CGPoint thumbPoint;
      thumbPoint = [aTouch locationInView:aTouch.view];
      //printf("touchesBegan %d x %d!\n", (int)thumbPoint.x, (int)thumbPoint.y);

      if (mPrimaryTouchHash==0)
         mPrimaryTouchHash = [aTouch hash];

      if (mMultiTouch)
      {
         Event mouse(etTouchBegin, thumbPoint.x, thumbPoint.y);
         mouse.value = [aTouch hash];
         if (mouse.value==mPrimaryTouchHash)
            mouse.flags |= efPrimaryTouch;
         mStage->OnMouseEvent(mouse);
      }
      else
      {
         Event mouse(etMouseDown, thumbPoint.x, thumbPoint.y);
         mouse.flags |= efLeftDown;
         mouse.flags |= efPrimaryTouch;
         mStage->OnMouseEvent(mouse);
      }

   }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
   NSArray *touchArr = [touches allObjects];
   NSInteger touchCnt = [touchArr count];

   for(int i=0;i<touchCnt;i++)
   {
      UITouch *aTouch = [touchArr objectAtIndex:i];

      CGPoint thumbPoint;
      thumbPoint = [aTouch locationInView:aTouch.view];

      if (mMultiTouch)
      {
         Event mouse(etTouchMove, thumbPoint.x, thumbPoint.y);
         mouse.value = [aTouch hash];
         if (mouse.value==mPrimaryTouchHash)
            mouse.flags |= efPrimaryTouch;
         mStage->OnMouseEvent(mouse);
      }
      else
      {
         Event mouse(etMouseMove, thumbPoint.x, thumbPoint.y);
         mouse.flags |= efLeftDown;
         mouse.flags |= efPrimaryTouch;
         mStage->OnMouseEvent(mouse);
      }
   }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
   NSArray *touchArr = [touches allObjects];
   NSInteger touchCnt = [touchArr count];

   for(int i=0;i<touchCnt;i++)
   {
      UITouch *aTouch = [touchArr objectAtIndex:i];

      CGPoint thumbPoint;
      thumbPoint = [aTouch locationInView:aTouch.view];
//printf("touchesEnd %d x %d!\n", (int)thumbPoint.x, (int)thumbPoint.y);

      if (mMultiTouch)
      {
         Event mouse(etTouchEnd, thumbPoint.x, thumbPoint.y);
         mouse.value = [aTouch hash];
         if (mouse.value==mPrimaryTouchHash)
         {
            mouse.flags |= efPrimaryTouch;
            mPrimaryTouchHash = 0;
         }
         mStage->OnMouseEvent(mouse);
      }
      else
      {
         Event mouse(etMouseUp, thumbPoint.x, thumbPoint.y);
         mouse.flags |= efPrimaryTouch;
         mStage->OnMouseEvent(mouse);
      }
   }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
   [self touchesEnded:touches withEvent:event];
}

- (void) enableMultitouch:(bool)withEnable
{
   mMultiTouch = withEnable;
   if (mMultiTouch)
      [self setMultipleTouchEnabled:YES];
   else
      [self setMultipleTouchEnabled:NO];
}


- (void) enableKeyboard:(bool)withEnable
{
   if (mKeyboardEnabled!=withEnable)
   {
       mKeyboardEnabled = withEnable;
       if (mKeyboardEnabled)
       {
          // Setup a dummy textfield to make iPhone think we have a text field - but
          //  delegate all the events to ourselves..
          if (mTextField==nil)
          {
             #ifndef OBJC_ARC
             mTextField = [[[UITextField alloc] initWithFrame: CGRectMake(0,0,0,0)] autorelease];
             #else
             mTextField = [[UITextField alloc] initWithFrame: CGRectMake(0,0,0,0)];
             #endif

             mTextField.delegate = self;
             /* placeholder so there is something to delete! (from SDL code) */
             mTextField.text = @" ";   
   
             /* set UITextInputTrait properties, mostly to defaults */
             mTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
             mTextField.autocorrectionType = UITextAutocorrectionTypeNo;
             mTextField.enablesReturnKeyAutomatically = NO;
             mTextField.keyboardAppearance = UIKeyboardAppearanceDefault;
             mTextField.keyboardType = UIKeyboardTypeDefault;
             mTextField.returnKeyType = UIReturnKeyDefault;
             mTextField.secureTextEntry = NO;   
             mTextField.hidden = YES;

        [self addSubview: mTextField];

          }
          [mTextField becomeFirstResponder];
       }
       else
       {
          [mTextField resignFirstResponder];
       }
   }
}


- (void) drawView:(id)sender
{
   mStage->OnRedraw();
}

- (void) onPoll:(id)sender
{
   mStage->OnPoll();
}


- (void) layoutSubviews
{
   mStage->OnOGLResize((CAEAGLLayer*)self.layer);
}

#ifndef OBJC_ARC
- (void) dealloc
{
    if (mStage) mStage->DecRef();
    if (mTextField)
       [mTextField release];
   
    [super dealloc];
}
#endif

@end


double sgWakeUp = 0.0;




// --- UIStageViewController ----------------------------------------------------------
// The NMEAppDelegate + UIStageViewController control the application when created in stand-alone mode


@interface UIStageViewController : UIViewController
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
- (void)loadView;
@end


@implementation UIStageViewController

#define UIInterfaceOrientationPortraitMask (1 << UIInterfaceOrientationPortrait)
#define UIInterfaceOrientationLandscapeLeftMask  (1 << UIInterfaceOrientationLandscapeLeft)
#define UIInterfaceOrientationLandscapeRightMask  (1 << UIInterfaceOrientationLandscapeRight)
#define UIInterfaceOrientationPortraitUpsideDownMask  (1 << UIInterfaceOrientationPortraitUpsideDown)
   
#define UIInterfaceOrientationLandscapeMask   (UIInterfaceOrientationLandscapeLeftMask | UIInterfaceOrientationLandscapeRightMask)
#define UIInterfaceOrientationAllMask  (UIInterfaceOrientationPortraitMask | UIInterfaceOrientationLandscapeLeftMask | UIInterfaceOrientationLandscapeRightMask | UIInterfaceOrientationPortraitUpsideDownMask)
#define UIInterfaceOrientationAllButUpsideDownMask  (UIInterfaceOrientationPortraitMask | UIInterfaceOrientationLandscapeLeftMask | UIInterfaceOrientationLandscapeRightMask)

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
   if (gFixedOrientation >= 0)
      return interfaceOrientation == gFixedOrientation;
   Event evt(etShouldRotate);
   evt.value = interfaceOrientation;
   sgNMEView->mStage->OnEvent(evt);
   return evt.result == 2;
}

- (NSUInteger)supportedInterfaceOrientations
{
   int mask = 1;
   bool isOverridden = false;

   if ([self shouldAutorotateToInterfaceOrientation:UIInterfaceOrientationLandscapeLeft]) {
      isOverridden = true;
      mask = UIInterfaceOrientationLandscapeLeftMask;
   }

   if ([self shouldAutorotateToInterfaceOrientation:UIInterfaceOrientationLandscapeRight]) {
      if (isOverridden) {
         mask |= UIInterfaceOrientationLandscapeRightMask;
      } else {
         isOverridden = true;
         mask = UIInterfaceOrientationLandscapeRightMask;
      }
   }

   if ([self shouldAutorotateToInterfaceOrientation:UIInterfaceOrientationPortraitUpsideDown]) {
      if (isOverridden) {
         mask |= UIInterfaceOrientationPortraitUpsideDownMask;
      } else {
         isOverridden = true;
         mask = UIInterfaceOrientationPortraitUpsideDownMask;
      }
   }

   if ([self shouldAutorotateToInterfaceOrientation:UIInterfaceOrientationPortrait]) {
      if (isOverridden) {
         mask |= UIInterfaceOrientationPortraitMask;
      } else {
         isOverridden = true;
         mask = UIInterfaceOrientationPortraitMask;
      }
   }

   if (!isOverridden) {
      mask = UIInterfaceOrientationAllMask;
   }
   return mask;
}

- (void)loadView
{
   UIStageView *view = [[UIStageView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
   self.view = view;
}

@end




// --- NMEAppDelegate ----------------------------------------------------------

class UIViewFrame : public nme::Frame
{
public:
   UIStageView *mView;

   UIViewFrame(UIStageView *inView) : mView(inView) { }

   virtual void SetTitle()  { }
   virtual void SetIcon() { }
   virtual Stage *GetStage()  { return mView->mStage; }

};



@interface NMEAppDelegate : NSObject <UIApplicationDelegate>
{
   UIWindow *window;
   UIViewController *controller;
}
@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet UIViewController *controller;

@end


@implementation NMEAppDelegate

@synthesize window;
@synthesize controller;

- (void) applicationDidFinishLaunching:(UIApplication *)application
{
   UIWindow *win = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
   window = win;
   [window makeKeyAndVisible];
   UIStageViewController  *c = [[UIStageViewController alloc] init];
   controller = c;
   [win addSubview:c.view];
   self.window.rootViewController = c;
   nme_app_set_active(true);
   application.idleTimerDisabled = YES;
   sOnFrame( new UIViewFrame((UIStageView *)c.view) );
}

- (void) applicationWillResignActive:(UIApplication *)application
{
   nme_app_set_active(false);
}

- (void) applicationDidBecomeActive:(UIApplication *)application
{
   nme_app_set_active(true);
}

- (void) applicationWillTerminate:(UIApplication *)application
{
   nme_app_set_active(false);
}

#ifndef OBJC_ARC
- (void) dealloc
{
   [window release];
   [controller release];
   [super dealloc];
}
#endif

@end



// --- Extenal Interface -------------------------------------------------------

void EnableKeyboard(bool inEnable)
{
   [ sgNMEView enableKeyboard:inEnable];
}


// Used when view is created as a child, rather than by application
UIView *nmeParentView = 0;


namespace nme
{

Stage *IPhoneGetStage()
{
   return sgNMEView->mStage;
}

void StartAnimation()
{
   if (sgNMEView)
   {
      [sgNMEView startAnimation];
   }
}
void PauseAnimation()
{
   if (sgNMEView)
   {
      [sgNMEView stopAnimation];
   }
}
void ResumeAnimation()
{
   if (sgNMEView)
   {
      [sgNMEView startAnimation];
   }
}
void StopAnimation()
{
   if (sgNMEView)
   {
      [sgNMEView stopAnimation];
   }
}

void SetNextWakeUp(double inWakeUp)
{
   sgWakeUp = inWakeUp;
}

int GetDeviceOrientation()
{

   return ( [UIDevice currentDevice].orientation );
}

double CapabilitiesGetPixelAspectRatio()
{
   //CGRect screenBounds = [[UIScreen mainScreen] bounds];
   //return screenBounds.size.width / screenBounds.size.height;
   return 1;
   
}
   
double CapabilitiesGetScreenDPI()
{
   CGFloat screenScale = 1;
    if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]) {
        screenScale = [[UIScreen mainScreen] scale];
    }
    float dpi;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        dpi = 132 * screenScale;
    } else if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
        dpi = 163 * screenScale;
    } else {
        dpi = 160 * screenScale;
    }
    
   return dpi;
}

double CapabilitiesGetScreenResolutionX()
{
   CGRect screenBounds = [[UIScreen mainScreen] bounds];
   if([[UIScreen mainScreen] respondsToSelector: NSSelectorFromString(@"scale")])
   {
      CGFloat screenScale = [[UIScreen mainScreen] scale];
      CGSize screenSize = CGSizeMake(screenBounds.size.width * screenScale, screenBounds.size.height * screenScale);
      return screenSize.width;
   }
   return screenBounds.size.width;
}
   
double CapabilitiesGetScreenResolutionY()
{
   CGRect screenBounds = [[UIScreen mainScreen] bounds];
   if([[UIScreen mainScreen] respondsToSelector: NSSelectorFromString(@"scale")])
   {
      CGFloat screenScale = [[UIScreen mainScreen] scale];
      CGSize screenSize = CGSizeMake(screenBounds.size.width * screenScale, screenBounds.size.height * screenScale);
      return screenSize.height;
   }
   return screenBounds.size.height;   
}   
   
   
void CreateMainFrame(FrameCreationCallback inCallback,
   int inWidth,int inHeight,unsigned int inFlags, const char *inTitle, Surface *inIcon )
{
   sOnFrame = inCallback;
   int argc = 0;// *_NSGetArgc();
   char **argv = 0;// *_NSGetArgv();

   sgAllowShaders = ( inFlags & wfAllowShaders );
   sgHasDepthBuffer = ( inFlags & wfDepthBuffer );
   sgHasStencilBuffer = ( inFlags & wfStencilBuffer );
   sgEnableMSAA2 = ( inFlags & wfHW_AA );
   sgEnableMSAA4 = ( inFlags & wfHW_AA_HIRES );

   //can't have a stencil buffer on it's own, 
   if(sgHasStencilBuffer && !sgHasDepthBuffer)
      sgHasDepthBuffer = true;

   if (nmeParentView)
   {
      double width = nmeParentView.frame.size.width;
      double height = nmeParentView.frame.size.height;
      UIStageView *view = [[UIStageView alloc] initWithFrame:CGRectMake(0.0,0.0,width,height)];

      [nmeParentView  addSubview:view];
      // application.idleTimerDisabled = YES;
      sOnFrame( new UIViewFrame(view) );

      [view startAnimation];
      nmeParentView = 0;
   }
   else
   {
      #ifndef OBJC_ARC
      NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
      #endif
      UIApplicationMain(argc, argv, nil, @"NMEAppDelegate");
      #ifndef OBJC_ARC
      [pool release];
      #endif
   }
}

bool GetAcceleration(double &outX, double &outY, double &outZ)
{
#ifdef IPHONESIM
   return false;
#else
   if (!sgCmManager || sgHasAccelerometer)
      return false;

   CMAcceleration a = sgCmManager.accelerometerData.acceleration;

   outX = a.x;
   outY = a.y;
   outZ = a.z;
   return true;
#endif
}


// Since you can't write data in your bundle, I think you need to save user data
// under a different file name to avoid confilcts.
// getPathForResource does not work in sub-directories on iPod 3.1.3
// "resourcePath" is soooo much nicer.
FILE *OpenRead(const char *inName)
{
   FILE *result = 0;

   if (inName[0]=='/')
   {
      result = fopen(inName,"rb");
   }
   else
   {
      std::string asset = GetResourcePath() + gAssetBase + inName;
      //printf("Try asset %s.\n", asset.c_str());
      result = fopen(asset.c_str(),"rb");

      if (!result)
      {
         std::string doc;
       GetSpecialDir(DIR_USER, doc);
       doc += gAssetBase + inName;
         //printf("Try doc %s.\n", doc.c_str());
         result = fopen(doc.c_str(),"rb");
      }
   }
   //printf("%s -> %p\n", inName, result);
   return result;
}



//[ddc]
FILE *OpenOverwrite(const char *inName)
{
    std::string asset = gAssetBase + inName;
    NSString *str = [[NSString alloc] initWithUTF8String:asset.c_str()];

    NSString *strWithoutInitialDash;    
    if([str hasPrefix:@"/"]){
     strWithoutInitialDash = [str substringFromIndex:1];
     }
     else {
     strWithoutInitialDash = str;
     }

    //NSLog(@"file name I'm wrinting to = %@", strWithoutInitialDash);
    
    //NSString *path = [[NSBundle mainBundle] pathForResource:str ofType:nil];
    NSString  *path = [[[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingString: @"/"] stringByAppendingString: strWithoutInitialDash];
    //NSLog(@"path name I'm wrinting to = %@", path);
    

   if ( ! [[NSFileManager defaultManager] fileExistsAtPath: [path stringByDeletingLastPathComponent]] ) {
        //NSLog(@"directory doesn't exist, creating it");
      [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent] withIntermediateDirectories:YES  attributes:nil error:NULL];
   }

    FILE * result = fopen([path cStringUsingEncoding:1],"w");
    #ifndef OBJC_ARC
    [str release];
    #endif
    return result;
}



void nmeSetParentView(void *inParent)
{
   nmeParentView = (UIView *)inParent;
}


void nmeReparentNMEView(void *inParent)
{
   UIView *parent = (UIView *)inParent;

   if (sgNMEView!=nil)
   {
      [parent  addSubview:sgNMEView];

      [sgNMEView startAnimation];
   }
}


} // namespace nme



extern "C"
{

void nme_app_set_active(bool inActive)
{
   if (IPhoneGetStage())
   {
      Event evt(inActive ? etActivate : etDeactivate);
      IPhoneGetStage()->HandleEvent(evt);
   }

   if (inActive)
      nme::StartAnimation();
   else
      nme::StopAnimation();
}


}
