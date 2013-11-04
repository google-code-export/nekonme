import sys.FileSystem;

class Build
{
   static var buildArgs = new Array<String>();

   public static function main()
   {
      mkdir("bin");
      mkdir("unpack");
      buildZ("1.2.3");
   }

   public static function mkdir(inDir:String)
   {
      FileSystem.createDirectory(inDir);
   }

   public static function untar(inTar:String)
   {
      run("tar", [ "xvzf", "tars/" + inTar, "-C", "unpack" ]);
   }

   public static function run(inExe:String, inArgs:Array<String>)
   {
      Sys.command(inExe,inArgs);
   }

   public static function copy(inFrom:String, inTo:String)
   {
      if (FileSystem.isDirectory(inTo))
         inTo += "/" + haxe.io.Path.withoutDirectory(inFrom);
      sys.io.File.copy(inFrom,inTo);
   }

   public static function runIn(inDir:String, inExe:String, inArgs:Array<String>)
   {
     var oldPath:String = Sys.getCwd();
     Sys.setCwd(inDir);
     Sys.command(inExe,inArgs);
     Sys.setCwd(oldPath);
   }

   public static function buildZ(inVer:String)
   {
      untar("zlib-" + inVer + ".tgz");
      copy("buildfiles/zlib.xml", 'unpack/zlib-$inVer');
      runIn('unpack/zlib-$inVer', "haxelib", ["run", "hxcpp", "zlib.xml"].concat(buildArgs));
   }
}

