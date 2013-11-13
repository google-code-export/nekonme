import nme.display.Sprite;
import nme.net.NetStream;
import nme.events.StageVideoEvent;


/*
The following steps summarize how to use a StageVideo object to play a video:

Attach a NetStream object using StageVideo.attachNetStream().
Play the video using NetStream.play().
Listen for the StageVideoEvent.RENDER_STATE event on the StageVideo object to determine the status of playing the video. Receipt of this event also indicates that the width and height properties of the video have been initialized or changed. 
Listen for the VideoEvent.RENDER_STATE event on the Video object. This event provides the same statuses as StageVideoEvent.RENDER_STATE, so you can also use it to determine whether GPU acceleration is available. Receipt of this event also indicates that the width and height properties of the video have been initialized or changed. (Not supported for AIR 2.5 for TV.)
*/

class Main extends Sprite
{
   public function new()
   {
      super();

      // In flash, we must wait for StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY
      if (stage.stageVideo.length<1)
      {
         trace("No video available");
      }
      else
      {
          var stream = new NetStream(); 
          //stream.addEventListener(NetStatusEvent.NET_STATUS,netStatusHandler); 
          //stream.addEventListener(AsyncErrorEvent.ASYNC_ERROR, asyncErrorHandler); A
 
          var video = stage.stageVideo[0];
          video.attachNetStream(stream);
          video.addEventListener(StageVideoEvent.RENDER_STATE, onRenderState);
          stream.play("http://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4");
      }
   }

   function onRenderState(ev:StageVideoEvent)
   {
      trace(ev.status);
   }
}


