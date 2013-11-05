import sys.FileSystem;

class Build
{
   static var buildArgs = new Array<String>();

   public static function main()
   {
      //buildArgs.push("-Dandroid");

      mkdir("bin");
      mkdir("unpack");
      mkdir("include");

      buildZ("1.2.3");
      buildPng("1.2.24");
      buildJpeg("6b");
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
      var dir = 'unpack/zlib-$inVer';
      copy("buildfiles/zlib.xml", dir);
      runIn(dir, "haxelib", ["run", "hxcpp", "zlib.xml"].concat(buildArgs));
      copy('$dir/zlib.h',"include");
      copy('$dir/zconf.h',"include");
   }

   public static function buildPng(inVer:String)
   {
      untar("libpng-" + inVer + ".tgz");
      var dir = 'unpack/libpng-$inVer';
      copy("buildfiles/png.xml", dir);
      runIn(dir, "haxelib", ["run", "hxcpp", "png.xml"].concat(buildArgs));
      copy('$dir/png.h',"include");
      copy('$dir/pngconf.h',"include");
   }

   public static function buildJpeg(inVer:String)
   {
      untar("jpeg-" + inVer + ".tgz");
      var dir = 'unpack/jpeg-$inVer';
      var configs = [ "h", "mac", "iphoneos", "vc", "linux" ];
      for(config in configs)
         copy('configs/jconfig.$config', dir);

      copy("buildfiles/jpeg.xml", dir);
      runIn(dir, "haxelib", ["run", "hxcpp", "jpeg.xml"].concat(buildArgs));
      for(config in configs)
         copy('configs/jconfig.$config', "include");
      copy('$dir/jpeglib.h',"include");
      copy('$dir/jmorecfg.h',"include");
   }

}

