
module DDC.Driver.Build.Main
        ( buildSpec
        , buildComponent
        , buildModule)
where
import DDC.Driver.Command.Compile
import DDC.Driver.Command.Make
import DDC.Driver.Config
import DDC.Build.Spec
import DDC.Build.Interface.Base
import System.FilePath
import Data.Maybe
import Control.Monad
import Control.Monad.Trans.Error
import Control.Monad.IO.Class
import qualified DDC.Core.Check         as C
import qualified DDC.Core.Tetra         as Tetra
import qualified DDC.Data.SourcePos     as BP
import qualified System.Directory       as Directory


-- | Annotated interface type.
type InterfaceAA
        = Interface (C.AnTEC BP.SourcePos Tetra.Name) ()


---------------------------------------------------------------------------------------------------
-- | Build all the components defined by a build spec.
buildSpec  
        :: Config               -- ^ Build config.
        -> Spec                 -- ^ Build spec.
        -> ErrorT String IO ()

buildSpec config spec
 = do   mapM_   (buildComponent config spec) 
                (specComponents spec)


---------------------------------------------------------------------------------------------------
-- | Build a single component of a build spec.
buildComponent 
        :: Config               -- ^ Build config.
        -> Spec                 -- ^ Build spec that mentions the module.
        -> Component            -- ^ Component to build.
        -> ErrorT String IO ()

buildComponent config spec component@SpecLibrary{}
 = do
        when (configLogBuild config)
         $ liftIO $ putStrLn $ "* Building " ++ specLibraryName component

        buildLibrary config spec component []
         $ specLibraryTetraModules component

        return ()

buildComponent config spec component@SpecExecutable{}
 = do   
        when (configLogBuild config)
         $ liftIO $ putStrLn $ "* Building " ++ specExecutableName component

        buildExecutable config spec component [] 
                (specExecutableTetraMain  component)
                (specExecutableTetraOther component)

        return ()


---------------------------------------------------------------------------------------------------
-- | Build a library consisting of several modules.
buildLibrary 
        :: Config               -- ^ Build config
        -> Spec                 -- ^ Build spec for the library
        -> Component            -- ^ Component defining the library
        -> [InterfaceAA]        -- ^ Interfaces that we've already loaded.
        -> [String]             -- ^ Names of modules still to build
        -> ErrorT String IO ()

buildLibrary config spec component interfaces0 ms0
 = go interfaces0 ms0
 where
        go _interfaces []
         = return ()

        go interfaces (m : more)
         = do   
                moreInterfaces  <- buildModule config spec component interfaces m

                let interfaces' = interfaces ++ moreInterfaces
                go  interfaces' more


---------------------------------------------------------------------------------------------------
-- | Build an executable consisting of several modules.
buildExecutable
        :: Config               -- ^ Build config.
        -> Spec                 -- ^ Build spec that mentions the module.
        -> Component            -- ^ Build component that mentions the module.
        -> [InterfaceAA]        -- ^ Interfaces of modules that we've already loaded.
        -> String               -- ^ Name  of main module.
        -> [String]             -- ^ Names of dependency modules
        -> ErrorT String IO ()

buildExecutable config spec component interfaces0 mMain msOther0
 = go interfaces0 msOther0
 where  
        go interfaces [] 
         = do   
                let dirs        = configModuleBaseDirectories config
                path            <- locateModuleFromPaths dirs mMain "ds"

                when (configLogBuild config)
                 $ liftIO 
                 $ do   putStrLn $ "  - compiling " ++ mMain

                cmdMake config interfaces path

        go interfaces (m : more)
         = do   
                moreInterfaces  <- buildModule config spec component interfaces m

                let interfaces' =  interfaces ++ moreInterfaces
                go  interfaces' more


---------------------------------------------------------------------------------------------------
-- | Build a single module.
buildModule
        :: Config               -- ^ Build config.
        -> Spec                 -- ^ Build spec that mentions the module.
        -> Component            -- ^ Build component that mentions the module.
        -> [InterfaceAA]        -- ^ Interfaces of modules that we've already loaded.
        -> String               -- ^ Module name.
        -> ErrorT String IO [InterfaceAA]

buildModule config _spec _component interfaces name
 = do   
        when (configLogBuild config)
         $ liftIO 
         $ do   putStrLn $ "  - compiling " ++ name

        let dirs = configModuleBaseDirectories config
        path     <- locateModuleFromPaths dirs name "ds"

        cmdCompile config interfaces path


---------------------------------------------------------------------------------------------------
locateModuleFromPaths
        :: [FilePath]           -- ^ Base paths.
        -> String               -- ^ Module name.
        -> String               -- ^ Source file extension
        -> ErrorT String IO FilePath

locateModuleFromPaths pathsBase name ext
 = do
        mPaths  <- liftIO 
                $  liftM catMaybes
                $  mapM  (\d -> locateModuleFromPath d name ext) pathsBase

        case mPaths of
         []        -> throwError $ unlines 
                   $  [ "Cannot locate source for module '" ++ name  ++ "' from base directories:" ]
                   ++ ["    " ++ dir | dir <- pathsBase]

         [path]    -> return path

         paths     -> throwError $ unlines
                   $  [ "Source for module '" ++ name ++ "' found at multiple paths:" ]
                   ++ ["    " ++ dir | dir <- paths]


-- | Given the path of a .build spec, and a module name, yield the path where
--   the source of the module should be.
locateModuleFromPath 
        :: FilePath             -- ^ Base path.
        -> String               -- ^ Module name.
        -> String               -- ^ Source file extension.
        -> IO (Maybe FilePath)

locateModuleFromPath pathBase name ext
 = let  go str 
         | elem '.' str
         , (n, '.' : rest)      <- span (/= '.') str
         = n   </> go rest

         | otherwise
         = str <.> ext

   in do
        let pathFile    = pathBase </> go name
        exists          <- Directory.doesFileExist pathFile
        if exists 
         then return $ Just pathFile
         else return Nothing


 



