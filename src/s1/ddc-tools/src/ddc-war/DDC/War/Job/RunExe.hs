
module DDC.War.Job.RunExe
        ( Spec         (..)
        , Result       (..)
        , resultSuccess
        , build)
where
import BuildBox.Build.Benchmark
import BuildBox.Command.File
import BuildBox.Command.System
import BuildBox.Data.Physical
import BuildBox
import BuildBox.Pretty
import Data.List


-- | Run a binary.
data Spec
        = Spec
        { -- | The main source file this binary was built from.
          specFileSrc    :: FilePath

          -- | Binary to run.
        , specFileBin    :: FilePath

          -- | Command line arguments to pass.
        , specCmdArgs    :: [String]

          -- | Put what binary said on stdout here.
        , specRunStdout  :: FilePath

          -- | Put what binary said on stderr here.
        , specRunStderr  :: FilePath

          -- | True if we expect the executable to succeed.
        , specShouldSucceed :: Bool }
        deriving Show


data Result
        = ResultSuccess Seconds
        | ResultUnexpectedFailure
        | ResultUnexpectedSuccess


resultSuccess :: Result -> Bool
resultSuccess result
 = case result of
        ResultSuccess{} -> True
        _               -> False


instance Pretty Result where
 ppr result
  = case result of
        ResultSuccess seconds
         -> string "success"  %% parens (ppr seconds)

        ResultUnexpectedFailure
         -> string "failed"

        ResultUnexpectedSuccess
         -> string "unexpected"


-- | Run a binary
build :: Spec -> Build Result
build (Spec     _fileName
                mainBin args
                mainRunOut mainRunErr
                shouldSucceed)
 = do
        needs mainBin

        -- Run the binary.
        (time, (code, strOut, strErr))
         <- timeBuild
         $  systemTee False (mainBin ++ " " ++ intercalate " " args) ""

        -- Write its output to files.
        atomicWriteFile mainRunOut strOut
        atomicWriteFile mainRunErr strErr

        case code of
         ExitFailure _
          | shouldSucceed       -> return ResultUnexpectedFailure

         ExitSuccess
          | not shouldSucceed   -> return ResultUnexpectedSuccess

         _                      -> return $ ResultSuccess time
