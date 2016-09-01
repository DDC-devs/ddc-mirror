
module DDC.Core.Collect.FreeT
        ( FreeVarConT(..)
        , freeVarsT)
where
import DDC.Core.Collect.BindStruct
import DDC.Type.Exp
import DDC.Type.Env             (KindEnv)
import Data.Set                 (Set)
import qualified DDC.Type.Env   as Env
import qualified DDC.Type.Sum   as Sum
import qualified Data.Set       as Set


-- | Collect the free type variables in a type.
freeVarsT 
        :: Ord n
        => KindEnv n -> Type n
        -> Set (Bound n)
freeVarsT kenv tt
 = fst $ freeVarConT kenv tt


instance BindStruct (Type n) n where
 slurpBindTree tt
  = case tt of
        TVar u          -> [BindUse BoundSpec u]
        TCon tc         -> slurpBindTree tc
        TAbs b t        -> [bindDefT BindTAbs   [b] [t]]
        TApp t1 t2      -> slurpBindTree t1 ++ slurpBindTree t2
        TForall b t     -> [bindDefT BindForall [b] [t]]
        TSum ts         -> concatMap slurpBindTree $ Sum.toList ts


instance BindStruct (TyCon n) n where
 slurpBindTree tc
  = case tc of
        TyConBound u k  -> [BindCon BoundSpec u (Just k)]
        _               -> []


class FreeVarConT (c :: * -> *) where
  -- | Collect the free type variables and constructors used in a thing.
  freeVarConT 
        :: Ord n 
        => KindEnv n -> c n 
        -> (Set (Bound n), Set (Bound n))


instance FreeVarConT Type where
 freeVarConT kenv tt
  = case tt of
        TVar u  
         -> if Env.member u kenv
                then (Set.empty, Set.empty)
                else (Set.singleton u, Set.empty)

        TCon tc
         | TyConBound u _ <- tc -> (Set.empty, Set.singleton u)
         | otherwise            -> (Set.empty, Set.empty)

        TAbs b t
         -> freeVarConT (Env.extend b kenv) t

        TApp t1 t2
         -> let (vs1, cs1)      = freeVarConT kenv t1
                (vs2, cs2)      = freeVarConT kenv t2
            in  ( Set.union vs1 vs2
                , Set.union cs1 cs2)

        TForall b t
         -> freeVarConT (Env.extend b kenv) t

        TSum ts
         -> let (vss, css)      = unzip $ map (freeVarConT kenv) 
                                $ Sum.toList ts
            in  (Set.unions vss, Set.unions css)


