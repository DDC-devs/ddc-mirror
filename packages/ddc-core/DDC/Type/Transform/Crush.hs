module DDC.Type.Transform.Crush
        ( crushSomeT
        , crushEffect )
where
import DDC.Type.Predicates
import DDC.Type.Compounds
import DDC.Type.Exp
import DDC.Type.Env             (TypeEnv)
import qualified DDC.Type.Sum   as Sum


-- | Crush compound effects and closure terms.
--   We check for a crushable term before calling crushT because that function
--   will recursively crush the components. 
--   As equivT is already recursive, we don't want a doubly-recursive function
--   that tries to re-crush the same non-crushable type over and over.
--
crushSomeT :: Ord n => TypeEnv n -> Type n -> Type n
crushSomeT caps tt
 = {-# SCC crushSomeT #-}
   case tt of
        TApp (TCon tc) _
         -> case tc of
                TyConSpec    TcConDeepRead   -> crushEffect caps tt
                TyConSpec    TcConDeepWrite  -> crushEffect caps tt
                TyConSpec    TcConDeepAlloc  -> crushEffect caps tt
                _                            -> tt

        _ -> tt


-- | Crush compound effect terms into their components.
--
--   For example, crushing @DeepRead (List r1 (Int r2))@ yields @(Read r1 + Read r2)@.
--
crushEffect 
        :: Ord n 
        => TypeEnv n            -- ^ Globally available capabilities.
        -> Effect n             -- ^ Type to crush. 
        -> Effect n

crushEffect caps tt
 = {-# SCC crushEffect #-}
   case tt of
        TVar{}          -> tt
        TCon{}          -> tt

        TForall b t
         -> TForall b $ crushEffect caps t

        TSum ts         
         -> TSum
          $ Sum.fromList (Sum.kindOfSum ts)   
          $ map (crushEffect caps)
          $ Sum.toList ts

        TApp t1 t2
         -- Head Read.
         |  Just (TyConSpec TcConHeadRead, [t]) <- takeTyConApps tt
         -> case takeTyConApps t of

             -- Type has a head region.
             Just (TyConBound _ k, (tR : _)) 
              |  (k1 : _, _) <- takeKFuns k
              ,  isRegionKind k1
              -> tRead tR

             -- Type has no head region.
             -- This happens with  case () of { ... }
             Just (TyConSpec  TcConUnit, [])
              -> tBot kEffect

             Just (TyConBound _ _,       _)     
              -> tBot kEffect

             _ -> tt

         -- Deep Read.
         -- See Note: Crushing with higher kinded type vars.
         | Just (TyConSpec TcConDeepRead, [t]) <- takeTyConApps tt
         -> case takeTyConApps t of
             Just (TyConBound _ k, ts)
              | (ks, _)  <- takeKFuns k
              , length ks == length ts
              , Just effs       <- sequence $ zipWith makeDeepRead ks ts
              -> crushEffect caps $ TSum $ Sum.fromList kEffect effs

             _ -> tt

         -- Deep Write
         -- See Note: Crushing with higher kinded type vars.
         | Just (TyConSpec TcConDeepWrite, [t]) <- takeTyConApps tt
         -> case takeTyConApps t of
             Just (TyConBound _ k, ts)
              | (ks, _)  <- takeKFuns k
              , length ks == length ts
              , Just effs       <- sequence $ zipWith makeDeepWrite ks ts
              -> crushEffect caps $ TSum $ Sum.fromList kEffect effs

             _ -> tt 

         -- Deep Alloc
         -- See Note: Crushing with higher kinded type vars.
         | Just (TyConSpec TcConDeepAlloc, [t]) <- takeTyConApps tt
         -> case takeTyConApps t of
             Just (TyConBound _ k, ts)
              | (ks, _)  <- takeKFuns k
              , length ks == length ts
              , Just effs       <- sequence $ zipWith makeDeepAlloc ks ts
              -> crushEffect caps $ TSum $ Sum.fromList kEffect effs

             _ -> tt


         | otherwise
         -> TApp (crushEffect caps t1) (crushEffect caps t2)


-- | If this type has first order kind then wrap with the 
--   appropriate read effect.
makeDeepRead :: Kind n -> Type n -> Maybe (Effect n)
makeDeepRead k t
        | isRegionKind  k       = Just $ tRead t
        | isDataKind    k       = Just $ tDeepRead t
        | isClosureKind k       = Just $ tBot kEffect
        | isEffectKind  k       = Just $ tBot kEffect
        | otherwise             = Nothing


-- | If this type has first order kind then wrap with the 
--   appropriate read effect.
makeDeepWrite :: Kind n -> Type n -> Maybe (Effect n)
makeDeepWrite k t
        | isRegionKind  k       = Just $ tWrite t
        | isDataKind    k       = Just $ tDeepWrite t
        | isClosureKind k       = Just $ tBot kEffect
        | isEffectKind  k       = Just $ tBot kEffect
        | otherwise             = Nothing


-- | If this type has first order kind then wrap with the 
--   appropriate read effect.
makeDeepAlloc :: Kind n -> Type n -> Maybe (Effect n)
makeDeepAlloc k t
        | isRegionKind  k       = Just $ tAlloc t
        | isDataKind    k       = Just $ tDeepAlloc t
        | isClosureKind k       = Just $ tBot kEffect
        | isEffectKind  k       = Just $ tBot kEffect
        | otherwise             = Nothing



{- [Note: Crushing with higher kinded type vars]
   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   We can't just look at the free variables here and wrap Read and DeepRead constructors
   around them, as the type may contain higher kinded type variables such as: (t a).
   Instead, we'll only crush the effect when all variable have first-order kind.
   When comparing types with higher order variables, we'll have to use the type
   equivalence checker, instead of relying on the effects to be pre-crushed.
-}
