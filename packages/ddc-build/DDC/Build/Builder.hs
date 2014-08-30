
module DDC.Build.Builder
        ( BuilderConfig (..)
        , Builder       (..)
        , BuilderResult (..)
        , builders

        , determineDefaultBuilder)
where
import DDC.Build.Platform
import DDC.Base.Pretty                          hiding ((</>))
import Data.List
import System.FilePath                         
import System.Exit
import System.Process
import qualified DDC.Core.Salt.Platform         as Llvm

-- | Configuration information for a builder that is not platform specific.
data BuilderConfig
        = BuilderConfig
        { -- | Directory that holds the source for the runtime system
          --   and base library.
          builderConfigBaseSrcDir       :: FilePath 

          -- | Directory that holds the shared objects for the runtime
          --   system and base library.
        , builderConfigBaseLibDir       :: FilePath

          -- | Runtime library link with.
        , builderConfigLibFile          :: FilePath -> FilePath -> FilePath }


-- | Actions to use to invoke external compilation tools.
data Builder
        = Builder
        { -- | The name of this platform.
          builderName           :: String

          -- | The platform the build is being performed on.
        , buildHost             :: Platform

          -- | The platform we're compiling code for.
        , buildTarget           :: Platform

          -- | The LLVM target specification.
          --   Gives the widths of pointers and primitive numeric types.
        , buildSpec             :: Llvm.Platform

          -- | Directory that holds the source for the runtime system
          --   and base library.
        , buildBaseSrcDir       :: FilePath

          -- | Directory that holds the shared objects for the runtime
          --   system and base library.
        , buildBaseLibDir       :: FilePath 

          -- | Invoke the C compiler
          --   to compile a .c file into a .o file.
        , buildCC               :: FilePath -> FilePath -> IO ()

          -- | Invoke the LLVM compiler
          --   to compile a .ll file into a .s file.
        , buildLlc              :: FilePath -> FilePath -> IO ()

          -- | Invoke the system assembler
          --   to assemble a .s file into a .o file.
        , buildAs               :: FilePath -> FilePath -> IO ()

          -- | Link an executable.
        , buildLdExe            :: [FilePath] -> FilePath -> IO () 

          -- | Link a static library.
        , buildLdLibStatic      :: [FilePath] -> FilePath -> IO ()

          -- | Link a shared library.
        , buildLdLibShared      :: [FilePath] -> FilePath -> IO () }


-- | The result of a build command.
--
--   We use these so that the called doesn't need to worry about
--   interpreting numeric exit codes. 
data BuilderResult
        -- | Build command completed successfully.
        = BuilderSuccess

        -- | Build command was cancelled or killed by the user.
        --   eg by Control-C on the console.
        | BuilderCanceled     

        -- | Build command failed. 
        --   There is probably something wrong with the generated file.
        --   Unrecognised exit codes also result in this BuilderResult.
        | BuilderFailed
        deriving (Show, Eq)


instance Show Builder where
 show builder
        = "Builder " ++ show (builderName builder)


instance Pretty Builder where
 ppr builder
        = vcat
        [ text "Builder Name : " <> text (builderName builder) 
        , empty
        , text "Host Platform"
        , indent 1 $ ppr $ buildHost builder 
        , empty
        , text "Target Platform"
        , indent 1 $ ppr $ buildTarget builder
        , empty
        , text "LLVM Target Spec"
        , indent 1 $ ppr $ buildSpec builder ]


-- builders -------------------------------------------------------------------
-- | All supported builders.
--   The host and target platforms are the same.
-- 
--   Supported builders are: 
--      @x86_32-darwin@, @x86_64-darwin@,
--      @x86_32-linux@,  @x86_64-linux@,
--      @x86_32-cygwin@,
--      @ppc32-linux@
--
builders :: BuilderConfig -> [Builder]
builders config
 =      [ builder_X8632_Darwin config
        , builder_X8664_Darwin config
        , builder_X8632_Linux  config 
        , builder_X8664_Linux  config
        , builder_PPC32_Linux  config ]


-- defaultBuilder -------------------------------------------------------------
-- | Determine the default builder based on the 'arch' and 'uname' commands.
--   This assumes that the 'host' and 'target' platforms are the same.
--
--   If we don't recognise the result of 'arch' or 'uname', or don't have 
--   a default builder config for this platform then `Nothing`.
determineDefaultBuilder :: BuilderConfig -> IO (Maybe Builder)
determineDefaultBuilder config
 = do   mPlatform       <- determineHostPlatform

        case mPlatform of
         Just (Platform ArchX86_32 OsDarwin)    
                -> return $ Just (builder_X8632_Darwin config)

         Just (Platform ArchX86_64 OsDarwin)    
                -> return $ Just (builder_X8664_Darwin config)

         Just (Platform ArchX86_32 OsLinux)
                -> return $ Just (builder_X8632_Linux  config)

         Just (Platform ArchX86_64 OsLinux)
                -> return $ Just (builder_X8664_Linux  config)

         Just (Platform ArchPPC_32 OsLinux)
                -> return $ Just (builder_PPC32_Linux  config)

         Just (Platform ArchX86_32 OsCygwin)
                -> return $ Just (builder_X8632_Cygwin config)

         Just (Platform ArchX86_32 OsMingw)
                -> return $ Just (builder_X8632_Mingw config)

         _      -> return Nothing


-- x86_32-darwin ----------------------------------------------------------------
builder_X8632_Darwin config
 =      Builder 
        { builderName           = "x86_32-darwin" 
        , buildHost             = Platform ArchX86_32 OsDarwin
        , buildTarget           = Platform ArchX86_32 OsDarwin
        , buildSpec             = Llvm.platform32
        , buildBaseSrcDir       = builderConfigBaseSrcDir config
        , buildBaseLibDir       = builderConfigBaseLibDir config

        -- Use -disable-cfi to disable Call Frame Identification (CFI) directives
        -- because the OSX system assembler doesn't support them.
        , buildLlc    
                = \llFile sFile
                -> doCmd "LLVM compiler"        [(2, BuilderCanceled)]
                [ "llc -O3 -march=x86 -relocation-model=pic -disable-cfi" 
                ,       llFile 
                , "-o", sFile ]

        , buildCC
                = \cFile oFile
                -> doCmd "C compiler"           [(2, BuilderCanceled)]
                [ "gcc -Werror -std=c99 -O3 -m32"
                , "-c", cFile
                , "-o", oFile
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/runtime"
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/primitive" ]

        , buildAs
                = \sFile oFile
                -> doCmd "assembler"            [(2, BuilderCanceled)]
                [ "as -arch i386"  
                , "-o", oFile
                ,       sFile ]

        , buildLdExe
                = \oFiles binFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                [ "gcc -m32" 
                , "-o", binFile
                , intercalate " " oFiles
                , builderConfigBaseLibDir config </> builderConfigLibFile config "libddc-runtime.a" "libddc-runtime.dylib" ]

        , buildLdLibStatic
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ ["ar r", libFile] ++ oFiles 

        , buildLdLibShared
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ [ "gcc -m32 -dynamiclib -undefined dynamic_lookup"
                  , "-o", libFile ] ++ oFiles
        }

-- x86_64-darwin --------------------------------------------------------------
builder_X8664_Darwin config
 =      Builder
        { builderName           = "x86_64-darwin"
        , buildHost             = Platform ArchX86_64 OsDarwin
        , buildTarget           = Platform ArchX86_64 OsDarwin
        , buildSpec             = Llvm.platform64
        , buildBaseSrcDir       = builderConfigBaseSrcDir config
        , buildBaseLibDir       = builderConfigBaseLibDir config

        -- Use -disable-cfi to disable Call Frame Identification (CFI) directives
        -- because the OSX system assembler doesn't support them.
        , buildLlc    
                = \llFile sFile
                -> doCmd "LLVM compiler"        [(2, BuilderCanceled)]
                [ "llc -O3 -march=x86-64 -relocation-model=pic -disable-cfi" 
                ,       llFile 
                , "-o", sFile ]

        , buildCC
                = \cFile oFile
                -> doCmd "C compiler"           [(2, BuilderCanceled)]
                [ "gcc -Werror -std=c99 -O3 -m64"
                , "-c", cFile
                , "-o", oFile
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/runtime"
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/primitive" ]

        , buildAs
                = \sFile oFile
                -> doCmd "assembler"            [(2, BuilderCanceled)]
                [ "as -arch x86_64"  
                , "-o", oFile
                ,       sFile ]

        , buildLdExe  
                = \oFiles binFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                [ "gcc -m64" 
                , "-o", binFile
                , intercalate " " oFiles
                , builderConfigBaseLibDir config </> builderConfigLibFile config "libddc-runtime.a" "libddc-runtime.dylib" ]

        , buildLdLibStatic
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ ["ar r", libFile] ++ oFiles 

        , buildLdLibShared
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ [ "gcc -m64 -dynamiclib -undefined dynamic_lookup"
                  , "-o", libFile ] ++ oFiles
        }


-- x86_32-linux ---------------------------------------------------------------
builder_X8632_Linux config
 =      Builder
        { builderName           = "x86_32-linux"
        , buildHost             = Platform ArchX86_32 OsLinux
        , buildTarget           = Platform ArchX86_32 OsLinux
        , buildSpec             = Llvm.platform32
        , buildBaseSrcDir       = builderConfigBaseSrcDir config
        , buildBaseLibDir       = builderConfigBaseLibDir config

        , buildLlc    
                = \llFile sFile
                -> doCmd "LLVM compiler"        [(2, BuilderCanceled)]
                [ "llc -O3 -march=x86 -relocation-model=pic" 
                ,       llFile 
                , "-o", sFile ]

        , buildCC
                = \cFile oFile
                -> doCmd "C compiler"           [(2, BuilderCanceled)]
                [ "gcc -Werror -std=c99 -O3 -m32 -fPIC"
                , "-c", cFile
                , "-o", oFile
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/runtime"
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/primitive" ]


        , buildAs
                = \sFile oFile
                -> doCmd "assembler"            [(2, BuilderCanceled)]
                [ "as --32"  
                , "-o", oFile
                ,       sFile ]

        , buildLdExe  
                = \oFiles binFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                [ "gcc -m32" 
                , "-o", binFile
                , intercalate " " oFiles
                , builderConfigBaseLibDir config </> builderConfigLibFile config "libddc-runtime.a" "libddc-runtime.so" ]

        , buildLdLibStatic
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ ["ar r", libFile] ++ oFiles 

        , buildLdLibShared
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ [ "gcc -shared", "-o", libFile ] ++ oFiles
        }


-- x86_64-linux ---------------------------------------------------------------
builder_X8664_Linux config
 =      Builder
        { builderName           = "x86_64-linux"
        , buildHost             = Platform ArchX86_64 OsLinux
        , buildTarget           = Platform ArchX86_64 OsLinux
        , buildSpec             = Llvm.platform64
        , buildBaseSrcDir       = builderConfigBaseSrcDir config
        , buildBaseLibDir       = builderConfigBaseLibDir config

        , buildLlc    
                = \llFile sFile
                -> doCmd "LLVM compiler"        [(2, BuilderCanceled)]
                [ "llc -O3 -march=x86-64 -relocation-model=pic" 
                , llFile 
                , "-o", sFile ]

        , buildCC
                = \cFile oFile
                -> doCmd "C compiler"           [(2, BuilderCanceled)]
                [ "gcc -Werror -std=c99 -O3 -m64 -fPIC"
                , "-c", cFile
                , "-o", oFile
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/runtime"
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/primitive" ]


        , buildAs
                = \sFile oFile
                -> doCmd "assembler"            [(2, BuilderCanceled)]
                [ "as --64"  
                , "-o", oFile
                , sFile ] 

        , buildLdExe  
                = \oFiles binFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                [ "gcc -m64"
                , "-o", binFile
                , intercalate " " oFiles
                , builderConfigBaseLibDir config </> builderConfigLibFile config "libddc-runtime.a" "libddc-runtime.so" ]

        , buildLdLibStatic
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ ["ar r", libFile] ++ oFiles 

        , buildLdLibShared
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ [ "gcc -shared", "-o", libFile ] ++ oFiles
        }


-- ppc32-linux ---------------------------------------------------------------
builder_PPC32_Linux config
 =      Builder
        { builderName           = "ppc32-linux"
        , buildHost             = Platform ArchPPC_32 OsLinux
        , buildTarget           = Platform ArchPPC_32 OsLinux
        , buildSpec             = Llvm.platform32
        , buildBaseSrcDir       = builderConfigBaseSrcDir config
        , buildBaseLibDir       = builderConfigBaseLibDir config

        , buildLlc    
                = \llFile sFile
                -> doCmd "LLVM compiler"        [(2, BuilderCanceled)]
                [ "llc -O3 -march=ppc32 -relocation-model=pic" 
                , llFile 
                , "-o", sFile ]

        , buildCC
                = \cFile oFile
                -> doCmd "C compiler"           [(2, BuilderCanceled)]
                [ "gcc -Werror -std=c99 -O3 -m32"
                , "-c", cFile
                , "-o", oFile
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/runtime"
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/primitive" ]

        , buildAs
                = \sFile oFile
                -> doCmd "assembler"            [(2, BuilderCanceled)]
                [ "as"
                , "-o", oFile
                , sFile ]

        , buildLdExe  
                = \oFiles binFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                [ "gcc -m32" 
                , "-o", binFile
                , intercalate " " $ map normalise oFiles
                , builderConfigBaseLibDir config </> builderConfigLibFile config "libddc-runtime.a" "libddc-runtime.so" ]

        , buildLdLibStatic
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ ["ar r", libFile] ++ oFiles 

        , buildLdLibShared
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ [ "gcc -shared", "-o", libFile ] ++ oFiles
        }


-- x86_32-cygwin ---------------------------------------------------------------
builder_X8632_Cygwin config
 =      Builder
        { builderName           = "x86_32-cygwin"
        , buildHost             = Platform ArchX86_32 OsCygwin
        , buildTarget           = Platform ArchX86_32 OsCygwin
        , buildSpec             = Llvm.platform32
        , buildBaseSrcDir       = builderConfigBaseSrcDir config
        , buildBaseLibDir       = builderConfigBaseLibDir config

        , buildLlc    
                = \llFile sFile
                -> doCmd "LLVM compiler"        [(2, BuilderCanceled)]
                [ "llc -O3 -march=x86 " 
                , normalise llFile
                , "-o", normalise sFile ]

        , buildCC
                = \cFile oFile
                -> doCmd "C compiler"           [(2, BuilderCanceled)]
                [ "gcc-4 -Werror -std=c99 -O3 -m32"
                , "-c", cFile
                , "-o", oFile
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/runtime"
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/primitive" ]

        , buildAs
                = \sFile oFile
                -> doCmd "assembler"            [(2, BuilderCanceled)]
                [ "as --32"
                , "-o", normalise oFile
                , normalise sFile ]

    -- Note on Cygwin we need to use 'gcc-4' explicitly because plain 'gcc'
    -- is a symlink, which Windows doesn't really support.
        , buildLdExe  
                = \oFiles binFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                [ "gcc-4 -m32" 
                , "-o", normalise binFile
                , intercalate " " $ map normalise oFiles
                , normalise $ builderConfigBaseLibDir config </> "libddc-runtime.a" ] -- configRuntimeLinkStrategy is ignored

        , buildLdLibStatic
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ ["ar r", libFile] ++ oFiles 

        , buildLdLibShared
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ [ "gcc -shared", "-o", libFile ] ++ oFiles
        }


-- x86_32-mingw ----------------------------------------------------------------
builder_X8632_Mingw config
 =      Builder
        { builderName           = "x86_32-mingw"
        , buildHost             = Platform ArchX86_32 OsMingw
        , buildTarget           = Platform ArchX86_32 OsMingw
        , buildSpec             = Llvm.platform32
        , buildBaseSrcDir       = builderConfigBaseSrcDir config
        , buildBaseLibDir       = builderConfigBaseLibDir config

        , buildLlc    
                = \llFile sFile
                -> doCmd "LLVM compiler"        [(2, BuilderCanceled)]
                [ "llc -O3 -march=x86 " 
                , normalise llFile
                , "-o", normalise sFile ]

        , buildCC
                = \cFile oFile
                -> doCmd "C compiler"           [(2, BuilderCanceled)]
                [ "gcc -Werror -std=c99 -O3 -m32"
                , "-c", cFile
                , "-o", oFile
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/runtime"
                , "-I" ++ builderConfigBaseSrcDir config </> "sea/primitive" ]

        , buildAs
                = \sFile oFile
                -> doCmd "assembler"            [(2, BuilderCanceled)]
                [ "as --32"
                , "-o", normalise oFile
                , normalise sFile ]

        , buildLdExe  
                = \oFiles binFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                [ "gcc -m32" 
                , "-o", normalise binFile
                , intercalate " " $ map normalise oFiles
                , normalise $ builderConfigBaseLibDir config </> "libddc-runtime.a" ] -- configRuntimeLinkStrategy is ignored

        , buildLdLibStatic
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ ["ar r", libFile] ++ oFiles 

        , buildLdLibShared
                = \oFiles libFile
                -> doCmd "linker"               [(2, BuilderCanceled)]
                $ [ "gcc -shared", "-o", libFile ] ++ oFiles
        }


-- Utils ----------------------------------------------------------------------
-- | Run a system command, and if it fails quit the program.
doCmd   :: String                       -- ^ Description of tool being invoked.
        -> [(Int, BuilderResult)]       -- ^ How to interpret exit codes.
        -> [String]                     -- ^ System command to run.
        -> IO ()

doCmd thing exitCodeMeanings cmdParts
 = do   
        code <- system cmd
        case code of
         ExitSuccess    
          -> return ()

         ExitFailure c
          |  Just meaning        <- lookup c exitCodeMeanings
          -> case meaning of
                BuilderSuccess  -> return ()
                BuilderCanceled -> exitWith $ ExitFailure 2
                BuilderFailed   -> die c

          | otherwise           -> die c

 where  cmd     = unwords cmdParts
        die c   = error
                $ unlines
                [ "System command failed when invoking external " ++ thing ++ "."
                , " Command was: " ++ cmd
                , " Exit code:   " ++ show c ]

