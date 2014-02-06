
module DDC.Driver.Command.Parse
        (cmdParseModule)
where
import DDC.Interface.Source
import DDC.Driver.Stage
import Control.Monad.Trans.Error
import Control.Monad.IO.Class
import System.FilePath
import qualified DDC.Core.Lexer as C


cmdParseModule :: Config -> Source -> String -> ErrorT String IO ()
cmdParseModule config source str
 | SourceFile filePath  <- source
 = case takeExtension filePath of
        ".dst"  -> cmdParseModule_tetra config filePath str
        ext     -> throwError $ "Cannot parse '" ++ ext ++ "' files."

 | otherwise
 = throwError "Cannot detect language."


cmdParseModule_tetra _config sourcePathName str
 = do   let tokens = C.lexModuleWithOffside sourcePathName 1 str
        liftIO $ putStrLn $ show tokens
        return ()
