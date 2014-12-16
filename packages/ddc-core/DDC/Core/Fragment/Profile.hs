
-- | A fragment profile determines what features a program can use.
module DDC.Core.Fragment.Profile
        ( Profile (..)
        , zeroProfile

        , Features(..)
        , zeroFeatures
        , setFeature)
where
import DDC.Core.Fragment.Feature
import DDC.Type.DataDef
import DDC.Type.Exp
import DDC.Type.Env                     (KindEnv, TypeEnv)
import DDC.Data.SourcePos
import qualified DDC.Type.Env           as Env
import Data.Text                        (Text)


-- | The fragment profile describes the language features and 
--   primitive operators available in the language.
data Profile n
        = Profile
        { -- | The name of this profile.
          profileName                   :: !String

          -- | Permitted language features.
        , profileFeatures               :: !Features

          -- | Primitive data type declarations.
        , profilePrimDataDefs           :: !(DataDefs n)

          -- | Kinds of primitive types.
        , profilePrimKinds              :: !(KindEnv n)

          -- | Types of primitive operators.
        , profilePrimTypes              :: !(TypeEnv n)

          -- | Check whether a type is an unboxed type.
          --   Some fragments limit how these can be used.
        , profileTypeIsUnboxed          :: !(Type n -> Bool) 

          -- | Check whether some name represents a hole that needs
          --   to be filled in by the type checker.
        , profileNameIsHole             :: !(Maybe (n -> Bool)) 

          -- | Embed a literal string in a name.
        , profileMakeStringName         :: Maybe (SourcePos -> Text -> n) }


-- | A language profile with no features or primitive operators.
--
--   This provides a simple first-order language.
zeroProfile :: Profile n
zeroProfile
        = Profile
        { profileName                   = "Zero"
        , profileFeatures               = zeroFeatures
        , profilePrimDataDefs           = emptyDataDefs
        , profilePrimKinds              = Env.empty
        , profilePrimTypes              = Env.empty
        , profileTypeIsUnboxed          = const False 
        , profileNameIsHole             = Nothing 
        , profileMakeStringName         = Nothing }


-- | A flattened set of features, for easy lookup.
data Features 
        = Features
        { featuresTrackedEffects        :: Bool
        , featuresTrackedClosures       :: Bool
        , featuresFunctionalEffects     :: Bool
        , featuresFunctionalClosures    :: Bool
        , featuresEffectCapabilities    :: Bool
        , featuresPartialPrims          :: Bool
        , featuresPartialApplication    :: Bool
        , featuresGeneralApplication    :: Bool
        , featuresNestedFunctions       :: Bool
        , featuresGeneralLetRec         :: Bool
        , featuresDebruijnBinders       :: Bool
        , featuresUnboundLevel0Vars     :: Bool
        , featuresUnboxedInstantiation  :: Bool
        , featuresNameShadowing         :: Bool
        , featuresUnusedBindings        :: Bool
        , featuresUnusedMatches         :: Bool
        }


-- | An emtpy feature set, with all flags set to `False`.
zeroFeatures :: Features
zeroFeatures
        = Features
        { featuresTrackedEffects        = False
        , featuresTrackedClosures       = False
        , featuresFunctionalEffects     = False
        , featuresFunctionalClosures    = False
        , featuresEffectCapabilities    = False
        , featuresPartialPrims          = False
        , featuresPartialApplication    = False
        , featuresGeneralApplication    = False
        , featuresNestedFunctions       = False
        , featuresGeneralLetRec         = False
        , featuresDebruijnBinders       = False
        , featuresUnboundLevel0Vars     = False
        , featuresUnboxedInstantiation  = False
        , featuresNameShadowing         = False
        , featuresUnusedBindings        = False
        , featuresUnusedMatches         = False }


-- | Set a language `Flag` in the `Profile`.
setFeature :: Feature -> Bool -> Features -> Features
setFeature feature val features
 = case feature of
        TrackedEffects          -> features { featuresTrackedEffects       = val }
        TrackedClosures         -> features { featuresTrackedClosures      = val }
        FunctionalEffects       -> features { featuresFunctionalEffects    = val }
        FunctionalClosures      -> features { featuresFunctionalClosures   = val }
        EffectCapabilities      -> features { featuresEffectCapabilities   = val }
        PartialPrims            -> features { featuresPartialPrims         = val }
        PartialApplication      -> features { featuresPartialApplication   = val }
        GeneralApplication      -> features { featuresGeneralApplication   = val }
        NestedFunctions         -> features { featuresNestedFunctions      = val }
        GeneralLetRec           -> features { featuresGeneralLetRec        = val }
        DebruijnBinders         -> features { featuresDebruijnBinders      = val }
        UnboundLevel0Vars       -> features { featuresUnboundLevel0Vars    = val }
        UnboxedInstantiation    -> features { featuresUnboxedInstantiation = val }
        NameShadowing           -> features { featuresNameShadowing        = val }
        UnusedBindings          -> features { featuresUnusedBindings       = val }
        UnusedMatches           -> features { featuresUnusedMatches        = val }

