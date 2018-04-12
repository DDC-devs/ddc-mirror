
module DDC.War.Job.Diff
        ( Spec         (..)
        , Result       (..)
        , resultSuccess
        , build)
where
import BuildBox.Command.File
import BuildBox.Command.System
import BuildBox


-- | Diff two files.
data Spec
        = Spec
        { -- | The baseline file.
          specFile       :: FilePath

          -- | File produced that we want to compare with the baseline.
        , specFileOut    :: FilePath

          -- | Put the result of the diff here.
        , specFileDiff   :: FilePath }
        deriving Show


-- | Result of a diff process.
data Result
        = ResultSame

        | ResultDiff
        { resultFileRef  :: FilePath
        , resultFileOut  :: FilePath
        , resultFileDiff :: FilePath }


-- | Check if this is a successful diff result.
resultSuccess :: Result -> Bool
resultSuccess result
 = case result of
        ResultSame{}    -> True
        _               -> False


instance Show Result where
 show result
  = case result of
        ResultSame      -> "ok"
        ResultDiff{}    -> "diff"


-- | Compare two files for differences.
build :: Spec -> Build Result
build (Spec fileRef fileOut fileDiff)
 = do   needs fileRef
        needs fileOut

        let diffExe     = "diff"

        -- Run the binary.
        (_code, strOut, _strErr)
         <- systemTee False
                (diffExe ++ " --ignore-space-change " ++ fileRef ++ " " ++ fileOut)
                ""

        -- Write its output to file.
        atomicWriteFile fileDiff strOut

        if strOut == ""
         then return $ ResultSame
         else return $ ResultDiff fileRef fileOut fileDiff

