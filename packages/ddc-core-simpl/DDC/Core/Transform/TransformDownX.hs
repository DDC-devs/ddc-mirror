
-- | General purpose tree walking boilerplate.
module DDC.Core.Transform.TransformDownX
        ( TransformDownMX(..)
        , transformDownX
        , transformDownX')
where
import DDC.Core.Module
import DDC.Core.Exp.Annot
import DDC.Type.Env             (KindEnv, TypeEnv)
import Data.Functor.Identity
import Control.Monad
import qualified DDC.Type.Env   as Env


-- | Top-down rewrite of all core expressions in a thing.
transformDownX
        :: forall (c :: * -> * -> *) a n
        .  (Ord n, TransformDownMX Identity c)
        => (KindEnv n -> TypeEnv n -> Exp a n -> Exp a n)       
                        -- ^ The worker function is given the current
                        --   kind and type environments.
        -> KindEnv n    -- ^ Initial kind environment.
        -> TypeEnv n    -- ^ Initial type environment.
        -> c a n        -- ^ Transform this thing.
        -> c a n

transformDownX f kenv tenv xx
        = runIdentity 
        $ transformDownMX 
                (\kenv' tenv' x -> return (f kenv' tenv' x)) 
                kenv tenv xx


-- | Like transformDownX, but without using environments.
transformDownX'
        :: forall (c :: * -> * -> *) a n
        .  (Ord n, TransformDownMX Identity c)
        => (Exp a n -> Exp a n)       
                        -- ^ The worker function is given the current
                        --      kind and type environments.
        -> c a n        -- ^ Transform this thing.
        -> c a n

transformDownX' f xx
        = transformDownX (\_ _ -> f) Env.empty Env.empty xx


-------------------------------------------------------------------------------
class TransformDownMX m (c :: * -> * -> *) where
 -- | Top-down monadic rewrite of all core expressions in a thing.
 transformDownMX
        :: Ord n
        => (KindEnv n -> TypeEnv n -> Exp a n -> m (Exp a n))
                        -- ^ The worker function is given the current
                        --      kind and type environments.
        -> KindEnv n    -- ^ Initial kind environment.
        -> TypeEnv n    -- ^ Initial type environment.
        -> c a n        -- ^ Transform this thing.
        -> m (c a n)


instance Monad m => TransformDownMX m Module where
 transformDownMX f kenv tenv !mm
  = do  x'    <- transformDownMX f kenv tenv $ moduleBody mm
        return  $ mm { moduleBody = x' }


instance Monad m => TransformDownMX m Exp where
 transformDownMX f kenv tenv !xx
  = {-# SCC transformDownMX #-} 
    f kenv tenv xx >>= \xx' -> 
     case xx' of
        XVar{}          -> return xx'
        XPrim{}         -> return xx'
        XCon{}          -> return xx'

        XLAM a b x1
         -> liftM3 XLAM (return a) (return b)
                        (transformDownMX f (Env.extend b kenv) tenv x1)

        XLam a b  x1    
         -> liftM3 XLam (return a) (return b) 
                        (transformDownMX f kenv (Env.extend b tenv) x1)

        XApp a x1 x2    
         -> liftM3 XApp (return a) 
                        (transformDownMX f kenv tenv x1) 
                        (transformDownMX f kenv tenv x2)

        XLet a lts x
         -> do  lts'      <- transformDownMX f kenv tenv lts
                let kenv' = Env.extends (specBindsOfLets lts')   kenv
                let tenv' = Env.extends (valwitBindsOfLets lts') tenv
                x'        <- transformDownMX f kenv' tenv' x
                return  $ XLet a lts' x'
                
        XCase a x alts
         -> liftM3 XCase (return a)
                         (transformDownMX f kenv tenv x)
                         (mapM (transformDownMX f kenv tenv) alts)

        XCast a c x       
         -> liftM3 XCast
                        (return a) (return c)
                        (transformDownMX f kenv tenv x)

        XType{}         -> return xx'
        XWitness{}      -> return xx'


instance Monad m => TransformDownMX m Lets where
 transformDownMX f kenv tenv xx
  = case xx of
        LLet b x
         -> liftM2 LLet (return b)
                        (transformDownMX f kenv tenv x)
        
        LRec bxs
         -> do  let (bs, xs) = unzip bxs
                let tenv'    = Env.extends bs tenv
                xs'          <- mapM (transformDownMX f kenv tenv') xs
                return       $ LRec $ zip bs xs'

        LPrivate{}
         -> return xx


instance Monad m => TransformDownMX m Alt where
 transformDownMX f kenv tenv alt
  = case alt of
        AAlt p@(PData _ bsArg) x
         -> let tenv'   = Env.extends bsArg tenv
            in  liftM2  AAlt (return p) 
                        (transformDownMX f kenv tenv' x)

        AAlt PDefault x
         ->     liftM2  AAlt (return PDefault)
                        (transformDownMX f kenv tenv x) 

