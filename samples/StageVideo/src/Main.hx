import nme.display.Sprite;
import nme.net.NetStream;
import nme.net.NetConnection;
import nme.events.StageVideoEvent;

import flash.events.AsyncErrorEvent;
import flash.events.NetStatusEvent;

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
      if (stage.stageVideos.length<1)
      {
         trace("No video available");
      }
      else
      {
          trace("Loading...");
          var video = stage.stageVideos[0];

          var nc = new NetConnection(); 
          nc.connect(null);
          nc.addEventListener(NetStatusEvent.NET_STATUS,netStatusHandler); 

          var stream = new NetStream(nc);
          var client:Dynamic = {};
          client.onMetaData = function(item:Dynamic)
          {
             trace("metaData " + item.width + "," + item.height);
             // Center video instance on Stage.
             video.viewPort = new nme.geom.Rectangle(
                (stage.stageWidth - item.width) / 2,
                (stage.stageHeight - item.height) / 2,
                item.width,
                item.height );
          };
          client.onPlayStatus = function(item:Dynamic)
          {
             trace("onPlayStatus " + item);
          };
          stream.client = client;

          stream.addEventListener(AsyncErrorEvent.ASYNC_ERROR, asyncErrorHandler);
 
          video.viewPort = new nme.geom.Rectangle(0,0,500,500);
          video.addEventListener(StageVideoEvent.RENDER_STATE, onRenderState);
          video.attachNetStream(stream);
          stream.play("http://download.wavetlan.com/SVV/Media/HTTP/H264/Talkinghead_Media/H264_test1_Talkinghead_mp4_480x360.mp4");

          // Seems flash needs this?
          addEventListener(nme.events.Event.ENTER_FRAME, function(_) { stream.bytesLoaded; } );
      }
   }

   function asyncErrorHandler(event:AsyncErrorEvent):Void 
   { 
      trace("asyncErrorHandler " + event);
   } 
   
   function netStatusHandler(event:NetStatusEvent):Void
   {
      trace("Net status " + event.info );
      switch (event.info.code)
      {
         case "NetConnection.Connect.Success":
            trace("You've connected successfully");
             
         case "NetStream.Publish.BadName":
            trace("Please check the name of the publishing stream" );
      }
   }

   function onRenderState(ev:StageVideoEvent)
   {
      trace(ev.status);
   }
}


