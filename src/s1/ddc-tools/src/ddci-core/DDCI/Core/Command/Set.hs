
-- | Display and toggle active interpreter modes.
module DDCI.Core.Command.Set
        ( Mode(..)
        , cmdSet)
where
import DDCI.Core.State
import DDCI.Core.Mode
import DDCI.Core.Output
import DDC.Core.Fragment
import DDC.Core.Simplifier.Parser
import DDC.Core.Transform.Reannotate
import DDC.Data.Pretty
import Control.Monad
import Data.Char
import Data.List
import qualified DDC.Build.Builder              as Build
import qualified DDC.Core.Check                 as Check
import qualified DDCI.Core.Rewrite              as R
import qualified Data.Map                       as Map
import qualified Data.Set                       as Set
import Prelude                                  hiding ((<$>))


cmdSet ::  State -> String -> IO State

-- Display the active modes.
cmdSet state []
 | Language bundle      <- stateLanguage state
 , fragment             <- bundleFragment   bundle
 , modules              <- bundleModules    bundle
 , simpl                <- bundleSimplifier bundle
 = do
        let langName    = profileName (fragmentProfile fragment)

        putStrLn $ renderIndent
         $ vcat
         [ vcat  [ text "Modes:      " <> string (show $ Set.toList $ stateModes state)
                 , text "Language:   " <> string langName
                 , text "Simplifier: " <> ppr  simpl
                 , text "Builder:    "
                       <> string (show $ liftM Build.builderName $ stateBuilder state) ]
         , vcat (text "With:       " : map ppr (Map.keys modules))
         , vcat (text "With Salt:  " : map ppr (Map.keys (stateWithSalt state))) ]

        return state

-- Toggle active modes.
cmdSet state cmd
 | ["lang", name]       <- words cmd
 = do   case lookup name languages of
         Just language
          -> do putStrLn "ok"
                return $ state { stateLanguage = language }

         Nothing
          -> do putStrLn "unknown language"
                return state

 | "trans" : rest       <- words cmd
 , Language bundle      <- stateLanguage state
 , modules              <- bundleModules       bundle
 , rules                <- bundleRewriteRules  bundle
 , mkNamT               <- bundleMakeNamifierT bundle
 , mkNamX               <- bundleMakeNamifierX bundle
 , fragment             <- bundleFragment      bundle
 = do   case parseSimplifier
                (fragmentReadName fragment)
                (SimplifierDetails
                        mkNamT mkNamX
                        (Map.assocs rules)
                        (Map.elems  modules))
                (concat $ intersperse " " rest) of

         Left _err
          -> do putStrLn $ "transform spec parse error"
                return state

         Right simpl
          -> do chatStrLn state "ok"
                let bundle'     = bundle { bundleSimplifier = simpl }
                return $ state { stateLanguage = Language bundle' }


 | ("rule", rest)       <- R.parseFirstWord cmd
 , Language bundle      <- stateLanguage state
 , fragment             <- bundleFragment      bundle
 , modules              <- bundleModules       bundle
 , rules                <- bundleRewriteRules  bundle
 = case R.parseRewrite fragment modules rest of
        Right (R.SetAdd name rule)
         -> do  chatStrLn state $ "ok, added " ++ name
                let rule'   = reannotate (\a -> a { Check.annotTail = ()}) rule
                let rules'  = Map.insert name rule' rules
                let bundle' = bundle { bundleRewriteRules = rules' }
                return $ state { stateLanguage = Language bundle' }

        Right (R.SetRemove name)
         -> do  chatStrLn state $ "ok, removed " ++ name
                let rules'  = Map.delete name rules
                let bundle' = bundle { bundleRewriteRules = rules' }
                return $ state { stateLanguage = Language bundle' }

        Right R.SetList
         -> do  let rules' = Map.toList rules
                mapM_ (uncurry $ R.showRule state 0) rules'
                return state

        Left e
         -> do  chatStrLn state e
                return state

 | "builder" : name : []     <- words cmd
 = do   config  <- getDefaultBuilderConfig
        mHost   <- Build.determineDefaultBuilderHost

        case mHost of
         Left err
          -> do  putStrLn $ renderIndent $ vcat
                        [ string "Cannot determine build environment."
                        , ppr err ]
                 return state

         Right host
          -> case find (\b -> Build.builderName b == name)
                       (Build.builders config host) of

                 Nothing
                  -> do  putStrLn "unknown builder"
                         return state

                 Just builder
                  -> do  chatStrLn state "ok"
                         return state { stateBuilder = Just builder }


 | "outputdir" : dir : []    <- words cmd
 = return $ state { stateOutputDir  = Just dir }

 | "output" : file : []      <- words cmd
 = return $ state { stateOutputFile = Just file }

 | otherwise
 = case parseModeChanges cmd of
        Just changes
         -> do  let state'  = foldr (uncurry adjustMode) state changes
                chatStrLn state "ok"
                return state'

        Nothing
         -> do  chatStrLn state "mode parse error"
                return state


-- | Parse a string of mode changes.
parseModeChanges :: String -> Maybe [(Bool, Mode)]
parseModeChanges str
        = sequence $ map parseModeChange $ words str


-- | Parse a mode change setting.
--   "Mode" or "+Mode" to enable. "-Mode" to disable.
parseModeChange  :: String -> Maybe (Bool, Mode)
parseModeChange str
 = case str of
        ('+' : strMode)
         | Just mode    <- readMode strMode
         -> Just (True, mode)

        ('/' : strMode)
         | Just mode    <- readMode strMode
         -> Just (False, mode)

        (c : strMode)
         | isUpper c
         , Just mode    <- readMode (c : strMode)
         -> Just (True, mode)

        _ -> Nothing


