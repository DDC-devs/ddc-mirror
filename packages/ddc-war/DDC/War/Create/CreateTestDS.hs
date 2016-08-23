
module DDC.War.Create.CreateTestDS
        (create)
where
import DDC.War.Create.Way
import DDC.War.Driver
import System.FilePath
import DDC.War.Job                              ()
import Data.Set                                 (Set)
import qualified DDC.War.Job.CompileDS          as CompileDS
import qualified DDC.War.Job.Diff               as Diff
import qualified Data.Set                       as Set


-- | Compile Test.ds files.
create :: Way -> Set FilePath -> FilePath -> Maybe Chain
create way allFiles filePath
 | takeFileName filePath == "Test.ds"
 = let  
        fileName        = takeFileName filePath
        sourceDir       = takeDirectory  filePath
        buildDir        = sourceDir </> "war-" ++ wayName way
        testName        = filePath

        mainDS          = sourceDir </> "Text.ds"
        mainSH          = sourceDir </> "Test.sh"
        testErrorCheck  = sourceDir </> replaceExtension fileName ".error.check"

        testCompStdout  = buildDir  </> replaceExtension fileName ".compile.stdout"
        testCompStderr  = buildDir  </> replaceExtension fileName ".compile.stderr"
        testCompDiff    = buildDir  </> replaceExtension fileName ".compile.stderr.diff"
        shouldSucceed   = not $ Set.member testErrorCheck allFiles

        -- Compile the .ds file
        compile         = jobOfSpec (JobId testName (wayName way))
                        $ CompileDS.Spec
                                filePath
                                (wayOptsComp way) ["-M50M"]
                                buildDir testCompStdout testCompStderr
                                Nothing shouldSucceed

        diffError       = jobOfSpec (JobId testName (wayName way))
                        $ Diff.Spec
                                testErrorCheck
                                testCompStderr testCompDiff

   in   -- Don't do anything if there is a Main.ds here.
        -- This other .ds file is probably a part of a larger program.
        if   Set.member mainDS allFiles
          || Set.member mainSH allFiles
           then Nothing
           else Just $ Chain
                        $ [compile] 
                        ++ (if shouldSucceed then [] else [diffError])

 | otherwise    = Nothing
