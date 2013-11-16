import nme.display.Sprite;

class Main extends Sprite
{
   public function new()
   {
      super();
      var gfx = graphics;

      gfx.lineStyle(1,0x000000);
      gfx.beginFill(0xff0000);
      gfx.drawCircle(200,200,100);
   }
}
