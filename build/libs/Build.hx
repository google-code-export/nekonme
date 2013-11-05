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
      buildOgg("1.3.0");
      buildVorbis("1.3.3");
      buildTheora("1.1.1");
      buildFreetype("2.5.0.1");
      buildCurl("7.21.4");
      buildSDL2("2.0.0");
      buildOpenal("1.15.1");
   }

   public static function mkdir(inDir:String)
   {
      FileSystem.createDirectory(inDir);
   }

   public static function untar(inTar:String,inBZ = false)
   {
      Sys.println("untar " + inTar);
      run("tar", [ inBZ ? "xf" : "xzf", "tars/" + inTar, "--no-same-owner", "-C", "unpack" ]);
   }

   public static function run(inExe:String, inArgs:Array<String>)
   {
      Sys.command(inExe,inArgs);
   }

   public static function copy(inFrom:String, inTo:String)
   {
      if (FileSystem.exists(inTo) && FileSystem.isDirectory(inTo))
         inTo += "/" + haxe.io.Path.withoutDirectory(inFrom);

      try {
      sys.io.File.copy(inFrom,inTo);
      }
      catch(e:Dynamic)
      {
         Sys.println("Could not copy " + inFrom + " to " + inTo + ":" + e);
         Sys.exit(1);
      }
   }

   public static function copyRecursive(inFrom:String, inTo:String)
   {
      if (!FileSystem.exists(inFrom))
      {
         Sys.println("Invalid copy : " + inFrom);
         Sys.exit(1);
      }
      if (FileSystem.isDirectory(inFrom))
      {
         mkdir(inTo);
         for(file in FileSystem.readDirectory(inFrom))
         {
            if (file.substr(0,1)!=".")
               copyRecursive(inFrom + "/" + file, inTo + "/" + file);
         }

      }
      else
         copy(inFrom,inTo);
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
      runIn(dir, "haxelib", ["run", "hxcpp", "zlib.xml", "-Dstatic_link"].concat(buildArgs));
      copy('$dir/zlib.h',"include");
      copy('$dir/zconf.h',"include");
   }

   public static function buildPng(inVer:String)
   {
      untar("libpng-" + inVer + ".tgz");
      var dir = 'unpack/libpng-$inVer';
      copy("buildfiles/png.xml", dir);
      runIn(dir, "haxelib", ["run", "hxcpp", "png.xml", "-Dstatic_link"].concat(buildArgs));
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
      runIn(dir, "haxelib", ["run", "hxcpp", "jpeg.xml", "-Dstatic_link"].concat(buildArgs));
      for(config in configs)
         copy('configs/jconfig.$config', "include");
      copy('$dir/jpeglib.h',"include");
      copy('$dir/jmorecfg.h',"include");
   }


   public static function buildOgg(inVer:String)
   {
      untar("libogg-" + inVer + ".tgz");
      var dir = 'unpack/libogg-$inVer';
      copy('configs/ogg-config_types.h', dir+"/include/ogg/config_types.h");
      copy("buildfiles/ogg.xml", dir);
      runIn(dir, "haxelib", ["run", "hxcpp", "ogg.xml", "-Dstatic_link"].concat(buildArgs));
      mkdir("include/ogg");
      copy('$dir/include/ogg/ogg.h',"include/ogg");
      copy('configs/ogg-config_types.h', "include/ogg/config_types.h");
      copy('$dir/include/ogg/os_types.h',"include/ogg");
   }

   public static function buildVorbis(inVer:String)
   {
      untar("libvorbis-" + inVer + ".tgz");
      var dir = 'unpack/libvorbis-$inVer';
      copy('patches/vorbis/os.h', dir+"/lib");
      copy("buildfiles/vorbis.xml", dir);
      runIn(dir, "haxelib", ["run", "hxcpp", "vorbis.xml", "-Dstatic_link"].concat(buildArgs));
      mkdir("include/vorbis");
      copy('$dir/include/vorbis/vorbisfile.h',"include/vorbis");
      copy('$dir/include/vorbis/codec.h',"include/vorbis");
      copy('$dir/include/vorbis/vorbisenc.h',"include/vorbis");
   }

   public static function buildTheora(inVer:String)
   {
      untar("libtheora-" + inVer + ".tar.bz2", true);
      var dir = 'unpack/libtheora-$inVer';
      copy('patches/theora/theoraplay.c', dir+"/lib/theoraplay.cpp");
      copy('patches/theora/theoraplay.h', dir+"/include");
      copy('patches/theora/theoraplay_cvtrgb.h', dir+"/include");
      copy("buildfiles/theora.xml", dir);
      runIn(dir, "haxelib", ["run", "hxcpp", "theora.xml", "-Dstatic_link"].concat(buildArgs));
      mkdir("include/theora");
      copy('$dir/include/theora/theora.h',"include/theora");
      copy('$dir/include/theora/theoradec.h',"include/theora");
      copy('$dir/include/theora/codec.h',"include/theora");
      copy('$dir/include/theoraplay.h',"include");
   }

   public static function buildFreetype(inVer:String)
   {
      untar("freetype-" + inVer + ".tgz");
      var dir = 'unpack/freetype-$inVer';
      copy("buildfiles/freetype.xml", dir);
      runIn(dir, "haxelib", ["run", "hxcpp", "freetype.xml", "-Dstatic_link"].concat(buildArgs));
      copy('$dir/include/ft2build.h',"include");
      copyRecursive('$dir/include/freetype',"include/freetype");
   }


   public static function buildCurl(inVer:String)
   {
      untar("curl-" + inVer + ".tgz");
      var dir = 'unpack/curl-$inVer';
      copy("configs/curl_config.gcc", dir+"/lib/curl_config.h");
      copy("patches/curl/curlbuild.h", dir+"/include/curl");
      copy("buildfiles/curl.xml", dir);
      runIn(dir, "haxelib", ["run", "hxcpp", "curl.xml", "-Dstatic_link" ].concat(buildArgs));
      copyRecursive('$dir/include/curl',"include/curl");
   }


   public static function buildSDL2(inVer:String)
   {
      untar("SDL2-" + inVer + ".tgz");
      var dir = 'unpack/SDL2-$inVer';
      copy("patches/SDL2/SDL_config_windows.h", dir+"/include");
      copy("patches/SDL2/SDL_stdinc.h", dir+"/include");
      copy("buildfiles/sdl2.xml", dir);
      runIn(dir, "haxelib", ["run", "hxcpp", "sdl2.xml", "-Dstatic_link"].concat(buildArgs));
      mkdir("include/SDL2");
      copyRecursive('$dir/include',"include/SDL2");
   }

   public static function buildOpenal(inVer:String)
   {
      untar("openal-soft-" + inVer + ".tgz");
      var dir = 'unpack/openal-soft-$inVer';
      copy("buildfiles/openal.xml", dir);
      runIn(dir, "haxelib", ["run", "hxcpp", "openal.xml", "-Dstatic_link"].concat(buildArgs));
   }

}

