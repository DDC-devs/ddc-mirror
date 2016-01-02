
-- | Source Tetra primitive type and kind environments.
module DDC.Source.Tetra.Env
        ( primKindEnv
        , kindOfPrimName

        , primTypeEnv 
        , typeOfPrimName
        
        , dataDefBool)
where
import DDC.Source.Tetra.Prim
import DDC.Source.Tetra.Exp
import DDC.Type.DataDef
import DDC.Type.Env             (Env)
import qualified DDC.Type.Env   as Env


-- Kinds ----------------------------------------------------------------------
-- | Kind environment containing kinds of primitive data types.
primKindEnv :: Env Name
primKindEnv = Env.setPrimFun kindOfPrimName Env.empty


-- | Take the kind of a primitive name.
--
--   Returns `Nothing` if the name isn't primitive. 
--
kindOfPrimName :: Name -> Maybe (Kind Name)
kindOfPrimName nn
 = case nn of
        NameTyCon tc            -> Just $ kindPrimTyCon tc
        _                       -> Nothing


-- Types ----------------------------------------------------------------------
-- | Type environment containing types of primitive operators.
primTypeEnv :: Env Name
primTypeEnv = Env.setPrimFun typeOfPrimName Env.empty


-- | Take the type of a name,
--   or `Nothing` if this is not a value name.
typeOfPrimName :: Name -> Maybe (Type Name)
typeOfPrimName dc
 = case dc of
        NameArith p
         -> Just $ typePrimArith p

        NameLitBool     _       -> Just $ tBool
        NameLitNat      _       -> Just $ tNat
        NameLitInt      _       -> Just $ tInt
        NameLitWord     _ bits  -> Just $ tWord bits
        NameLitTextLit  _       -> Just $ tTextLit

        _                       -> Nothing


-- | Data type definition for `Bool`.
dataDefBool :: DataDef Name
dataDefBool
 = makeDataDefAlg (NameTyCon PrimTyConBool) 
        [] 
        (Just   [ (NameLitBool True,  []) 
                , (NameLitBool False, []) ])
