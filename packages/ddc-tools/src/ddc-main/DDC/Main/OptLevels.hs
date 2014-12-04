
-- | Define the default optimisation levels.
module DDC.Main.OptLevels 
        ( getSimplLiteOfConfig
        , getSimplSaltOfConfig)
where
import DDC.Main.Config
import DDC.Driver.Command.Read
import DDC.Driver.Command.RewriteRules
import DDC.Build.Builder
import DDC.Build.Platform
import DDC.Core.Module
import DDC.Core.Transform.Inline
import DDC.Core.Transform.Namify
import DDC.Core.Transform.Reannotate
import DDC.Core.Simplifier                      (Simplifier)
import System.FilePath
import Control.Monad
import Data.List
import Data.Monoid
import Data.Maybe
import qualified DDC.Driver.Config              as D
import qualified DDC.Core.Fragment              as C
import qualified DDC.Core.Simplifier            as S
import qualified DDC.Core.Simplifier.Recipe     as S
import qualified DDC.Core.Lite                  as Lite
import qualified DDC.Core.Salt                  as Salt
import qualified DDC.Core.Salt.Runtime          as Salt
import qualified DDC.Build.Language.Salt        as Salt
import qualified DDC.Build.Language.Lite        as Lite
import qualified Data.Map                       as Map
import qualified Data.Set                       as Set


-- | Get the simplifier for Lite code from the config.
--   This also reads up all the modules we use for inliner templates.
--
--   We don't want to delay this until all arguments are parsed, 
--   because the simplifier spec also contains the list of modules used
--   as inliner templates, so we need to wait until they're all specified.
--
getSimplLiteOfConfig 
        :: Config -> D.Config
        -> Builder 
        -> Maybe FilePath -- ^ path of current module
        -> IO (Simplifier Int () Lite.Name)

getSimplLiteOfConfig config dconfig builder filePath
 = case configOptLevelLite config of
        OptLevel0       -> opt0_lite config 
        OptLevel1       -> opt1_lite config dconfig builder filePath


-- | Get the simplifier for Salt code from the config.
--
getSimplSaltOfConfig 
        :: Config  -> D.Config
        -> Builder
        -> Salt.Config
        -> Maybe FilePath -- ^ path of current module
        -> IO (Simplifier Int () Salt.Name)

getSimplSaltOfConfig config dconfig builder runtimeConfig filePath
 = case configOptLevelSalt config of
        OptLevel0       -> opt0_salt config 
        OptLevel1       -> opt1_salt config dconfig builder runtimeConfig filePath


-- Level 0 --------------------------------------------------------------------
-- This just passes the code through unharmed.

-- | Level 0 optimiser for Core Lite code.
opt0_lite :: Config -> IO (Simplifier Int () Lite.Name)
opt0_lite _
        = return $ S.Trans S.Id


-- | Level 0 optimiser for Core Salt code.
opt0_salt :: Config -> IO (Simplifier Int () Salt.Name)
opt0_salt _
        = return $ S.Trans S.Id


-- Level 1 --------------------------------------------------------------------
-- Do full optimsiations.

-- | Level 1 optimiser for Core Lite code.
opt1_lite 
        :: Config -> D.Config
        -> Builder
        -> Maybe FilePath -- ^ path of current module
        -> IO (Simplifier Int () Lite.Name)

opt1_lite config dconfig _builder filePath
 = do
        -- Auto-inline basic numeric code.
        let inlineModulePaths
                =  [ configBaseDir config </> "lite/base/Data/Numeric/Int.dcl"
                   , configBaseDir config </> "lite/base/Data/Numeric/Nat.dcl" ]
                ++ (configWithLite config)

        -- Load all the modules that we're using for inliner templates.
        --  If any of these don't load then the 'cmdReadModule' function 
        --  will display the errors.
        minlineModules
                <- liftM sequence
                $  mapM (cmdReadModule dconfig Lite.fragment)
                        inlineModulePaths

        let inlineModules
                = map (reannotate (const ()))
                $ fromMaybe (error "Imported modules do not parse.")
                            minlineModules

        let inlineSpec
                = Map.fromList
                [ (ModuleName ["Int"], InlineSpecAll (ModuleName ["Int"]) Set.empty)
                , (ModuleName ["Nat"], InlineSpecAll (ModuleName ["Nat"]) Set.empty) ]

        -- Optionally load the rewrite rules for each 'with' module
        rules <- mapM (\(m,file) -> cmdTryReadRules Lite.fragment (file ++ ".rules") m)
              $  inlineModules `zip` inlineModulePaths

        -- Load rules for target module as well
        modrules <- loadLiteRules dconfig filePath

        let rules' = concat rules ++ modrules

        -- Simplifier to convert to a-normal form.
        let normalizeLite
                = S.anormalize
                        (makeNamifier Lite.freshT)      
                        (makeNamifier Lite.freshX)


        -- Perform rewrites before inlining
        return  $  (S.Trans $ S.Rewrite rules')
                <> (S.Trans $ S.Inline
                            $ lookupTemplateFromModules inlineSpec inlineModules)
                <> S.Fix 5 (S.beta 
                                <> S.bubble      <> S.flatten 
                                <> normalizeLite <> S.forward
                                <> (S.Trans $ S.Rewrite rules'))


-- | Level 1 optimiser for Core Salt code.
opt1_salt 
        :: Config -> D.Config
        -> Builder
        -> Salt.Config
        -> Maybe FilePath -- ^ path of current module
        -> IO (Simplifier Int () Salt.Name)

opt1_salt config dconfig builder runtimeConfig filePath
 = do   
        -- Auto-inline the low-level code from the runtime system
        --   that constructs and destructs objects.
        let targetWidth
                = archPointerWidth $ platformArch $ buildTarget builder

        -- The runtime system code comes in different versions, 
        --  depending on the pointer width of the target architecture.
        let inlineModulePaths
                =  [ configBaseDir config 
                        </> "salt/runtime" ++ show targetWidth </> "Object.dcs"]
                ++ configWithSalt config

        -- Load all the modues that we're using for inliner templates.
        --  If any of these don't load then the 'cmdReadModule' function 
        --  will display the errors.
        minlineModules
                <- liftM sequence
                $  mapM (cmdReadModule dconfig Salt.fragment)
                        inlineModulePaths

        let inlineModules
                = map (reannotate (const ()))
                $ fromMaybe (error "Imported modules do not parse.")
                            minlineModules

        -- Inline everything from the Object module, except the listed functions. 
        -- We don't want these because they blow out the program size too much.
        let inlineSpec
                = Map.fromList
                [ ( ModuleName ["Object"]
                  , InlineSpecAll (ModuleName ["Object"]) 
                     $ Set.fromList 
                     $ map Salt.NameVar
                        [ "apply0", "apply1", "apply2", "apply4", "apply4", "applyZ"
                        , "copyAvailOfThunk"])]

        -- Optionally load the rewrite rules for each 'with' module
        rules <- mapM (\(m,file) -> cmdTryReadRules Salt.fragment (file ++ ".rules") m)
              $  inlineModules `zip` inlineModulePaths

        -- Load rules for target module as well
        modrules <- loadSaltRules dconfig builder runtimeConfig filePath

        let rules' = concat rules ++ modrules


        -- Simplifier to convert to a-normal form.
        let normalizeSalt
                = S.anormalize
                        (makeNamifier Salt.freshT)      
                        (makeNamifier Salt.freshX)
        
        -- Perform rewrites before inlining
        return  $  (S.Trans $ S.Rewrite rules')
                <> (S.Trans $ S.Inline 
                            $ lookupTemplateFromModules inlineSpec inlineModules)
                <> S.Fix 5 (S.beta 
                                <> S.bubble      <> S.flatten 
                                <> normalizeSalt <> S.forward
                                <> (S.Trans $ S.Rewrite rules'))


-- | Load rules for main module
loadLiteRules
    :: D.Config
    -> Maybe FilePath
    -> IO (S.NamedRewriteRules () Lite.Name)

loadLiteRules dconfig (Just filePath)
 | isSuffixOf ".dcl" filePath
 = do -- Parse module to get exported fn types
      modu     <- cmdReadModule' False dconfig Lite.fragment filePath
      case modu of
       Just mod' -> cmdTryReadRules Lite.fragment (filePath ++ ".rules")
                                    (reannotate (const ()) mod')
       Nothing   -> return []

loadLiteRules _ _
 = return []


-- | Load rules for main module
loadSaltRules
    :: D.Config
    -> Builder
    -> Salt.Config
    -> Maybe FilePath
    -> IO (S.NamedRewriteRules () Salt.Name)

loadSaltRules dconfig builder runtimeConfig (Just filePath)
 -- If the main module is a lite module, we need to load the lite then convert it to salt
 | isSuffixOf ".dcl" filePath
 = do modu     <- cmdReadModule' False dconfig Lite.fragment filePath
      let path' = (reverse $ drop 3 $ reverse filePath) ++ "dcs.rules"
      case modu of
       Just mod' ->
        case Lite.saltOfLiteModule (buildSpec builder) 
                    runtimeConfig
                    (C.profilePrimDataDefs Lite.profile) 
                    (C.profilePrimKinds    Lite.profile)
                    (C.profilePrimTypes    Lite.profile)
                    mod' 
         of  Left  _    -> return []
             Right mm'  -> cmdTryReadRules Salt.fragment path'
                                           (reannotate (const ()) mm')

       Nothing   -> return []

 | isSuffixOf ".dcs" filePath
 = do modu      <- cmdReadModule' False dconfig Salt.fragment filePath
      case modu of
       Just mod' -> cmdTryReadRules Salt.fragment (filePath ++ ".rules") (reannotate (const ()) mod')
       Nothing   -> return []

loadSaltRules _ _ _ _
 = return []


