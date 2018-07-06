
-- | Name resolution.
module DDC.Core.Check.Context.Resolve
        ( TyConThing(..)
        , resolveTyConThing
        , lookupTypeSyn
        , lookupDataType
        , lookupDataCtor)
where
import DDC.Core.Check.Base
import DDC.Core.Check.Context.Oracle    (TyConThing(..))
import qualified DDC.Core.Check.Context.Oracle  as Oracle
import qualified DDC.Core.Env.EnvT      as EnvT
import qualified DDC.Core.Env.EnvX      as EnvX
import qualified Data.Map.Strict        as Map



-------------------------------------------------------------------------------
-- | Resolve the name of a type constructor or synonym.
--   If we can't find one then throw an error in the `CheckM` monad.
resolveTyConThing
        :: (Ord n, Show n)
        => Context n -> n -> CheckM a n (TyConThing n, Kind n)

resolveTyConThing ctx n
 = lookupTyConThing ctx n
 >>= \case
        Nothing -> throw  $ ErrorType $ ErrorTypeUndefinedTypeCtor (UName n)
        Just tk -> return tk


lookupTyConThing
        :: (Ord n, Show n)
        => Context n -> n -> CheckM a n (Maybe (TyConThing n, Kind n))

lookupTyConThing ctx n
 -- Look for a data type declaration in the current module.
 | dataDefs      <- EnvX.envxDataDefs $ contextEnvX ctx
 , Just dataType <- Map.lookup n (dataDefsTypes dataDefs)
 = return $ Just
        ( TyConThingData n dataType
        , kindOfDataType dataType)

 -- Look for a data type or synonym declaration in an imported module.
 | Just oracle  <- contextOracle ctx
 = Oracle.resolveTyConThing oracle n
 >>= \case
        Nothing    -> return Nothing
        Just thing -> return $ Just (thing, Oracle.kindOfTyConThing thing)

 -- It's just not there.
 | otherwise    = return Nothing


-------------------------------------------------------------------------------
-- | Lookup the definition of a type synonym from its name.
--   If we can't find it then `Nothing`.
lookupTypeSyn
        :: (Ord n, Show n)
        => Context n -> n -> CheckM a n (Maybe (Type n))

lookupTypeSyn ctx n
 -- Look for synonyom in the current module.
 | Just tR  <- Map.lookup n $ EnvT.envtEquations $ contextEnvT ctx
 = return $ Just tR

 -- Look for synonym in imported modules.
 | Just oracle <- contextOracle ctx
 = Oracle.resolveTyConThing oracle n
 >>= \case
        Just (TyConThingSyn _ _ t) -> return $ Just t
        Just _  -> return Nothing
        Nothing -> return Nothing

 -- It's just not there.
 | otherwise    = return Nothing


-------------------------------------------------------------------------------
-- | Lookup the definition of a data type from its constructor name.
lookupDataType
        :: (Ord n, Show n)
        => Context n -> n -> CheckM a n (Maybe (DataType n))

lookupDataType ctx n
 -- Look for data type definition in the current module.
 | dataDefs      <- EnvX.envxDataDefs $ contextEnvX ctx
 , Just dataType <- Map.lookup n (dataDefsTypes dataDefs)
 = return $ Just dataType

 -- Look for data type definition in an imported module.
 | Just oracle <- contextOracle ctx
 = Oracle.resolveTyConThing oracle n
 >>= \case
        Nothing   -> return Nothing
        Just (TyConThingData _ dataType) -> return $ Just dataType
        Just _    -> return Nothing

 -- It's just not there.
 | otherwise    = return Nothing


-------------------------------------------------------------------------------
-- | Lookup the definition of a data constructor.
--   If we can't find it then `Nothing`.
lookupDataCtor
        :: (Ord n, Show n)
        => Context n -> n -> CheckM a n (Maybe (DataCtor n))

lookupDataCtor ctx n
 -- Look for data ctor in the current module.
 | dataDefs      <- EnvX.envxDataDefs $ contextEnvX ctx
 , Just dataCtor <- Map.lookup n (dataDefsCtors dataDefs)
 = return $ Just dataCtor

 -- Look for data ctor in imported modules.
 | Just oracle <- contextOracle ctx
 = Oracle.resolveDataCtor oracle n

 -- It's just not there.
 | otherwise    = return Nothing




{- This was from the old kind judgment.
   This checks the right of the bindings as well as returns the type.
   do we need to re-check at this point?

             -- The kinds of abstract imported type constructors are in the
             -- global kind environment.
             | Just k'          <- EnvT.lookupName n (contextEnvT ctx0)
             , UniverseSpec     <- uni
             -> return (TCon (TyConBound u k'), k')

             -- User defined data type constructors must be in the set of
             -- data defs. Attach the real kind why we're here.
             | Just def         <- Map.lookup n $ dataDefsTypes
                                                $ EnvX.envxDataDefs
                                                $ contextEnvX ctx0
             , UniverseSpec     <- uni
             -> let k'   = kindOfDataType def
                in  return (TCon (TyConBound u k'), k')

             -- For type synonyms, just re-check the right of the binding.
             | Just t'          <- Map.lookup n $ EnvT.envtEquations
                                                $ contextEnvT ctx0
             -> do  (tt', k', _) <- checkTypeM config ctx0 uni t' mode
                    return (tt', k')

             -- We don't have a type for this constructor.
             |  otherwise
             -> throw $ C.ErrorType $ ErrorTypeUndefinedTypeCtor u
-}
