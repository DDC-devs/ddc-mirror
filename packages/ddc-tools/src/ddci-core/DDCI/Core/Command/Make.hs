
module DDCI.Core.Command.Make
        (cmdMake)
where
import DDCI.Core.State
import DDC.Driver.Stage
import DDC.Driver.Source
import DDC.Build.Builder
import DDC.Build.Pipeline
import DDC.Build.Language
import System.Directory
import Data.Char
import Data.List
import Control.Monad
import Data.Maybe
import qualified DDC.Core.Pretty        as P


cmdMake :: State -> Source -> String -> IO ()
cmdMake state _source str
 = do
        -- Always treat the string as a filename
        let source   = SourceFile str

        -- Read in the source file.
        let filePath = dropWhile isSpace str
        exists  <- doesFileExist filePath
        when (not exists)
         $      error $ "No such file " ++ show filePath

        src     <- readFile filePath

        -- Determine the builder to use.
        mBuilder        <- determineDefaultBuilder defaultBuilderConfig
        let builder     =  fromMaybe (error "Can not determine host platform")
                                     mBuilder

        -- Slurp out the driver config we need from the DDCI state.
        let config      = driverConfigOfState state

        -- Decide what to do based on file extension.
        let make
                -- Make a Core Lite module.
                | isSuffixOf ".dcl" filePath
                = pipeText (nameOfSource source) (lineStartOfSource source) src
                $ stageLiteLoad     config source
                [ stageLiteOpt      config source  
                [ stageLiteToSalt   config source builder
                [ stageSaltOpt      config source
                [ stageSaltToLLVM   config source builder
                [ stageCompileLLVM  config source builder filePath True ]]]]]

                -- Make a Core Salt module.
                | isSuffixOf ".dce" filePath
                = pipeText (nameOfSource source) (lineStartOfSource source) src
                $ PipeTextLoadCore  fragmentSalt 
                [ stageSaltOpt      config source
                [ stageSaltToLLVM   config source builder
                [ stageCompileLLVM  config source builder filePath True ]]]

                -- Unrecognised.
                | otherwise
                = error $ "Don't know how to make " ++ filePath

        -- Print any errors that arose during compilation.
        errs    <- make
        mapM_ (putStrLn . P.renderIndent . P.ppr) errs
