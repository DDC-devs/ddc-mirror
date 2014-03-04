
-- | Language profile for Disciple Core Tetra
module DDC.Core.Tetra.Profile
        ( profile
        , lexModuleString
        , lexExpString
        , freshT
        , freshX)
where
import DDC.Core.Tetra.Prim
import DDC.Core.Tetra.Env
import DDC.Core.Fragment
import DDC.Core.Lexer
import DDC.Type.Exp
import DDC.Data.Token
import Control.Monad.State.Strict
import DDC.Type.Env             (Env)
import qualified DDC.Type.Env   as Env

-- | Language profile for Disciple Core Tetra.
profile :: Profile Name 
profile
        = Profile
        { profileName                   = "Tetra"
        , profileFeatures               = features
        , profilePrimDataDefs           = primDataDefs
        , profilePrimKinds              = primKindEnv
        , profilePrimTypes              = primTypeEnv
        , profileTypeIsUnboxed          = const False 
        , profileNameIsHole             = Just isNameHole }


features :: Features
features 
        = Features
        { featuresTrackedEffects        = True
        , featuresTrackedClosures       = False
        , featuresFunctionalEffects     = False
        , featuresFunctionalClosures    = False
        , featuresEffectCapabilities    = True
        , featuresPartialPrims          = True
        , featuresPartialApplication    = True
        , featuresGeneralApplication    = True
        , featuresNestedFunctions       = True
        , featuresDebruijnBinders       = True
        , featuresUnboundLevel0Vars     = False
        , featuresUnboxedInstantiation  = True
        , featuresNameShadowing         = True
        , featuresUnusedBindings        = True
        , featuresUnusedMatches         = True }


-- | Lex a string to tokens, using primitive names.
--
--   The first argument gives the starting source line number.
lexModuleString :: String -> Int -> String -> [Token (Tok Name)]
lexModuleString sourceName lineStart str
 = map rn $ lexModuleWithOffside sourceName lineStart str
 where rn (Token strTok sp) 
        = case renameTok readName strTok of
                Just t' -> Token t' sp
                Nothing -> Token (KJunk "lexical error") sp


-- | Lex a string to tokens, using primitive names.
--
--   The first argument gives the starting source line number.
lexExpString :: String -> Int -> String -> [Token (Tok Name)]
lexExpString sourceName lineStart str
 = map rn $ lexExp sourceName lineStart str
 where rn (Token strTok sp) 
        = case renameTok readName strTok of
                Just t' -> Token t' sp
                Nothing -> Token (KJunk "lexical error") sp


-- | Create a new type variable name that is not in the given environment.
freshT :: Env Name -> Bind Name -> State Int Name
freshT env bb
 = do   i       <- get
        put (i + 1)
        let n =  NameVar ("t" ++ show i)
        case Env.lookupName n env of
         Nothing -> return n
         _       -> freshT env bb


-- | Create a new value variable name that is not in the given environment.
freshX :: Env Name -> Bind Name -> State Int Name
freshX env bb
 = do   i       <- get
        put (i + 1)
        let n = NameVar ("x" ++ show i)
        case Env.lookupName n env of
         Nothing -> return n
         _       -> freshX env bb
