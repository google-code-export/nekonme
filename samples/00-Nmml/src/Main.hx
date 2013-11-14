import nme.display.Sprite;
import nme.text.TextField;

class Main extends Sprite
{
   static var sMain:Main;
   var text:TextField;

   public function new()
   {
      super();
      sMain = this;
      //var bmp = nme.Assets.getBitmapData("assets/Image.jpg");
      //gfx.beginBitmapFill(bmp);
      doSetColor(0xff0000);
      addEventListener( nme.events.Event.ENTER_FRAME, onUpdate );
      addEventListener( nme.events.MouseEvent.MOUSE_DOWN, onMouse );
      text = new TextField();
      text.text = "Hello!";
      addChild(text);
   }

   static public function setColor(inColor:Int)
   {
      sMain.doSetColor(inColor);
   }
 
   static public function setText(inText:String)
   {
      sMain.doSetText(inText);
   }
   
   public function doSetColor(inColor:Int)
   {
      var gfx = graphics;
      gfx.clear();
      gfx.beginFill(inColor);
      gfx.drawRect(10,10,200,200);
   }

 
   public function doSetText(inText:String)
   {
      text.text = inText;
   }


   function onMouse(evt)
   {
      trace(evt.stageX + "x" + evt.stageY);
   }


   function onUpdate(_)
   {
      x = x+1;
      if (x>100) x = 0;
   }

}
