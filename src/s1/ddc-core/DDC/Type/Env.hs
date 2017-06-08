
-- | Type environments.
--
--   An environment contains the types 
--     named bound variables,
--     named primitives, 
--     and a deBruijn stack for anonymous variables.
--
module DDC.Type.Env
        ( Env(..)
        , SuperEnv
        , KindEnv
        , TypeEnv

        -- * Construction
        , empty
        , singleton
        , extend
        , extends
        , union
        , unions

        -- * Conversion
        , fromList
        , fromListNT
        , fromTypeMap

        -- * Projections 
        , depth
        , member
        , memberBind
        , lookup
        , lookupName

        -- * Primitives
        , setPrimFun
        , isPrim

        -- * Lifting
        , lift)
where
import DDC.Type.Exp
import DDC.Type.Transform.BoundT
import Data.Maybe
import Data.Map                         (Map)
import Prelude                          hiding (lookup)
import qualified Data.Map.Strict        as Map
import qualified Prelude                as P
import Control.Monad


-- | A type environment.
data Env n
        = Env
        { -- | Types of named binders.
          envMap         :: !(Map n (Type n))

          -- | Types of anonymous deBruijn binders.
        , envStack       :: ![Type n] 
        
          -- | The length of the above stack.
        , envStackLength :: !Int

          -- | Types of baked in, primitive names.
        , envPrimFun     :: !(n -> Maybe (Type n)) }


-- | Type synonym to improve readability.
type SuperEnv n = Env n

-- | Type synonym to improve readability.
type KindEnv n  = Env n

-- | Type synonym to improve readability.
type TypeEnv n  = Env n


-- | An empty environment.
empty :: Env n
empty   = Env
        { envMap         = Map.empty
        , envStack       = [] 
        , envStackLength = 0
        , envPrimFun     = \_ -> Nothing }


-- | Construct a singleton type environment.
singleton :: Ord n => Bind n -> Env n
singleton b
        = extend b empty


-- | Extend an environment with a new binding.
--   Replaces bindings with the same name already in the environment.
extend :: Ord n => Bind n -> Env n -> Env n
extend bb env
 = case bb of
         BName n k      -> env { envMap         = Map.insert n k (envMap env) }
         BAnon   k      -> env { envStack       = k : envStack env 
                               , envStackLength = envStackLength env + 1 }
         BNone{}        -> env


-- | Extend an environment with a list of new bindings.
--   Replaces bindings with the same name already in the environment.
extends :: Ord n => [Bind n] -> Env n -> Env n
extends bs env
        = foldl (flip extend) env bs


-- | Set the function that knows the types of primitive things.
setPrimFun :: (n -> Maybe (Type n)) -> Env n -> Env n
setPrimFun f env
        = env { envPrimFun = f }


-- | Check if the type of a name is defined by the `envPrimFun`.
isPrim :: Env n -> n -> Bool
isPrim env n
        = isJust $ envPrimFun env n


-- | Convert a list of `Bind`s to an environment.
fromList :: Ord n => [Bind n] -> Env n
fromList bs
        = foldr extend empty bs


-- | Convert a list of name and types into an environment
fromListNT :: Ord n => [(n, Type n)] -> Env n
fromListNT nts
 = fromList [BName n t | (n, t) <- nts]


-- | Convert a map of names to types to a environment.
fromTypeMap :: Map n (Type n) -> Env n
fromTypeMap m
        = empty { envMap = m}


-- | Combine two environments.
--   If both environments have a binding with the same name,
--   then the one in the second environment takes preference.
union :: Ord n => Env n -> Env n -> Env n
union env1 env2
        = Env  
        { envMap         = envMap env1 `Map.union` envMap env2
        , envStack       = envStack       env2  ++ envStack       env1
        , envStackLength = envStackLength env2  +  envStackLength env1
        , envPrimFun     = \n -> envPrimFun env2 n `mplus` envPrimFun env1 n }


-- | Combine multiple environments,
--   with the latter ones taking preference.
unions :: Ord n => [Env n] -> Env n
unions envs
        = foldr union empty envs


-- | Check whether a bound variable is present in an environment.
member :: Ord n => Bound n -> Env n -> Bool
member uu env
        = isJust $ lookup uu env


-- | Check whether a binder is already present in the an environment.
--   This can only return True for named binders, not anonymous or primitive ones.
memberBind :: Ord n => Bind n -> Env n -> Bool
memberBind uu env
 = case uu of
        BName n _       -> Map.member n (envMap env)
        _               -> False


-- | Lookup a bound variable from an environment.
lookup :: Ord n => Bound n -> Env n -> Maybe (Type n)
lookup uu env
 = case uu of
        UName n 
         ->      Map.lookup n (envMap env) 
         `mplus` envPrimFun env n

        UIx i           -> P.lookup i (zip [0..] (envStack env))
        UPrim n _       -> envPrimFun env n


-- | Lookup a bound name from an environment.
lookupName :: Ord n => n -> Env n -> Maybe (Type n)
lookupName n env
        =       Map.lookup n (envMap env)
        `mplus` (envPrimFun env n)


-- | Yield the total depth of the deBruijn stack.
depth :: Env n -> Int
depth env       = envStackLength env


-- | Lift all free deBruijn indices in the environment by the given number of steps.
---
--  ISSUE #276: Delay lifting of indices in type environments.
--      The 'lift' function on type environments applies to every member of
--      the environment. We'd get better complexity by recording how many
--      levels all types should be lifted by, and only applying the real lift
--      function when the type is finally extracted.
--
lift  :: Ord n => Int -> Env n -> Env n
lift n env
        = Env
        { envMap         = Map.map (liftT n) (envMap env)
        , envStack       = map (liftT n) (envStack env)
        , envStackLength = envStackLength env
        , envPrimFun     = envPrimFun     env }

