
-- | Rewriting of anonymous binders to named binders.
module DDC.Core.Transform.Namify
        ( Namify        (..)
        , Namifier      (..)
        , makeNamifier
        , namifyUnique)
where
import DDC.Core.Module
import DDC.Core.Exp
import DDC.Core.Collect
import DDC.Type.Exp.Simple
import Control.Monad
import DDC.Type.Env             (Env, KindEnv, TypeEnv)
import qualified DDC.Type.Sum   as Sum
import qualified DDC.Type.Env   as Env
import Control.Monad.State.Strict


-- | Holds a function to rename binders,
--   and the state of the renamer as we decend into the tree.
data Namifier s n
        = Namifier
        { -- | Create a new name for this bind that is not in the given
          --   environment.
          namifierNew   :: Env n -> Bind n -> State s n

          -- | Holds the current environment during namification.
        , namifierEnv   :: Env n

          -- | Stack of debruijn binders that have been rewritten during
          --   namification.
        , namifierStack :: [Bind n] }


-- | Construct a new namifier.
makeNamifier
        :: (Env n -> Bind n -> State s n)
                        -- ^ Function to rename binders.
                        --   The name chosen cannot be a member of the given
                        ---  environment.
        -> Env n        -- ^ Starting environment of names we cannot use.
        -> Namifier s n

makeNamifier new env
        = Namifier new env []


-- | Namify a thing,
--   not reusing names already in the program.
namifyUnique
        :: (Ord n, Namify c, BindStruct (c n) n)
        => (KindEnv n -> Namifier s n)  -- ^ Make a namifier for level-1 names.
        -> (TypeEnv n -> Namifier s n)  -- ^ Make a namifier for level-0 names.
        -> c n
        -> State s (c n)

namifyUnique mkNamK mkNamT xx
 = let  (tbinds, xbinds) = collectBinds xx
        namK    = mkNamK (Env.fromList tbinds)
        namT    = mkNamT (Env.fromList xbinds)
   in   namify namK namT xx


-- Namify ---------------------------------------------------------------------
class Namify (c :: * -> *) where
 -- | Rewrite anonymous binders to named binders in a thing.
 namify :: Ord n
        => Namifier s n         -- ^ Namifier for type names (level-1)
        -> Namifier s n         -- ^ Namifier for exp names (level-0)
        -> c n                  -- ^ Rewrite binders in this thing.
        -> State s (c n)


instance Namify Type where
 namify tnam xnam tt
  = let down = namify tnam xnam
    in case tt of
        TVar u
         -> liftM TVar (rewriteT tnam u)

        TCon{}
         ->     return tt

        TAbs b t
         -> do  (tnam', b')     <- pushT tnam b
                t'              <- namify tnam' xnam t
                return  $ TAbs b' t'

        TApp t1 t2
         -> liftM2 TApp (down t1) (down t2)

        TForall b t
         -> do  (tnam', b')     <- pushT tnam b
                t'              <- namify tnam' xnam t
                return  $ TForall b' t'

        TSum ts
         -> do  ts'     <- mapM down $ Sum.toList ts
                return  $ TSum $ Sum.fromList (Sum.kindOfSum ts) ts'

        TRow r
         -> do  let (ls, ts) = unzip r
                ts'     <- mapM down ts
                return  $ TRow $ zip ls ts'


instance Namify (Module a) where
 namify tnam xnam mm
  = do  body'    <- namify tnam xnam $ moduleBody mm
        return  $ mm { moduleBody = body' }


instance Namify (Witness a) where
 namify tnam xnam ww
  = let down = namify tnam xnam
    in case ww of
        WVar  a u       -> liftM  (WVar  a) (rewriteX tnam xnam u)
        WCon{}          -> return ww
        WApp  a w1 w2   -> liftM2 (WApp  a) (down w1) (down w2)
        WType a t       -> liftM  (WType a) (down t)


instance Namify (Exp a) where
 namify tnam xnam xx
  = {-# SCC namify #-}
    let down = namify tnam xnam
    in case xx of
        XVar a u        -> liftM2 XVar (return a) (rewriteX tnam xnam u)
        XPrim{}         -> return xx
        XCon{}          -> return xx

        XAbs a (MType b) x
         -> do  (tnam', b')     <- pushT  tnam b
                x'              <- namify tnam' xnam x
                return $ XAbs a (MType b') x'

        XAbs a (MTerm b) x
         -> do  (xnam', b')     <- pushX  tnam xnam b
                x'              <- namify tnam xnam' x
                return $ XAbs a (MTerm b') x'

        XAbs a (MImplicit b) x
         -> do  (xnam', b')     <- pushX  tnam xnam b
                x'              <- namify tnam xnam' x
                return $ XAbs a (MImplicit b') x'

        XApp  a x1 x2
         ->     liftM3 XApp     (return a) (down x1)  (down x2)

        XLet  a (LLet b x1) x2
         -> do  x1'             <- namify tnam xnam x1
                (xnam', b')     <- pushX  tnam xnam b
                x2'             <- namify tnam xnam' x2
                return $ XLet a (LLet b' x1') x2'

        XLet a (LRec bxs) x2
         -> do  let (bs, xs)    = unzip bxs
                (xnam', bs')    <- pushXs tnam xnam bs
                xs'             <- mapM (namify tnam xnam') xs
                x2'             <- namify tnam xnam' x2
                return $ XLet a (LRec (zip bs' xs')) x2'

        XLet a (LPrivate b mt bs) x2
         -> do  (tnam', b')     <- pushTs tnam b
                (xnam', bs')    <- pushXs tnam' xnam bs
                x2'             <- namify tnam' xnam' x2
                return $ XLet a (LPrivate b' mt bs') x2'

        XCase a x1 alts -> liftM2 (XCase    a) (down x1)  (mapM down alts)
        XCast a c  x    -> liftM2 (XCast    a) (down c)   (down x)


instance Namify (Arg a) where
 namify tnam xnam aa
  = let down = namify tnam xnam
    in case aa of
        RType     t     -> fmap RType     $ down t
        RTerm     x     -> fmap RTerm     $ down x
        RImplicit x     -> fmap RImplicit $ down x
        RWitness  w     -> fmap RWitness  $ down w


instance Namify (Alt a) where
 namify tnam xnam (AAlt PDefault x)
  = liftM (AAlt PDefault) (namify tnam xnam x)

 namify tnam xnam (AAlt (PData u bs) x)
  = do  (xnam', bs')    <- pushXs tnam xnam bs
        x'              <- namify tnam xnam' x
        return  $ AAlt (PData u bs') x'


instance Namify (Cast a) where
 namify tnam xnam cc
  = let down = namify tnam xnam
    in case cc of
        CastWeakenEffect  eff   -> liftM CastWeakenEffect  (down eff)
        CastPurify w            -> liftM CastPurify (down w)
        CastBox                 -> return CastBox
        CastRun                 -> return CastRun


-- | Rewrite level-1 anonymous binders.
rewriteT :: Namifier s n
         -> Bound n
         -> State s (Bound n)

rewriteT tnam u
 = case u of
        UIx i
         -> case lookup i (zip [0..] (namifierStack tnam)) of
                Just (BName n _) -> return $ UName n
                _                -> return u

        _       -> return u


-- | Rewrite level-0 anonymous binders.
rewriteX :: Namifier s n
         -> Namifier s n
         -> Bound n
         -> State s (Bound n)

rewriteX _tnam xnam u
 = case u of
        UIx i
         -> case lookup i (zip [0..] (namifierStack xnam)) of
                Just (BName n _)
                 -> do  return  $ UName n
                _                -> return u

        _       -> return u


-- Push -----------------------------------------------------------------------
-- Chosing new names for anonymous binders and pushing them on the stack.

-- | Push a level-0 binder on the stack.
--   When we do this we also rewrite any indices in its type annotation.
pushX   :: Ord n
        => Namifier s n
        -> Namifier s n
        -> Bind n
        -> State s (Namifier s n, Bind n)

pushX tnam xnam b@(BNone t)
 = do   t'      <- namify tnam xnam t
        nx      <- namifierNew xnam (namifierEnv xnam) b
        let b'  = BName nx t'
        push xnam b'

pushX tnam xnam b
 = do   t'      <- namify tnam xnam (typeOfBind b)
        let b'  = replaceTypeOfBind t' b
        push xnam b'


-- | Push some level-0 binders on the stack.
--   When we do this we also rewrite their type annotations.
pushXs  :: Ord n
        => Namifier s n
        -> Namifier s n
        -> [Bind n]
        -> State s (Namifier s n, [Bind n])

pushXs _tnam xnam []
        = return (xnam, [])

pushXs tnam xnam (b:bs)
 = do   (xnam1, b')      <- pushX  tnam xnam  b
        (xnam2, bs')     <- pushXs tnam xnam1 bs
        return (xnam2, b' : bs')


-- | Push a level-1 binder on the stack.
pushT   :: Ord n
        => Namifier s n
        -> Bind n
        -> State s (Namifier s n, Bind n)
pushT   = push


pushTs  :: Ord n
        => Namifier s n
        -> [Bind n]
        -> State s (Namifier s n, [Bind n])
pushTs  tnam [] = return (tnam, [])
pushTs  tnam (b:bs)
 = do   (tnam1, b')  <- pushT  tnam  b
        (tnam2, bs') <- pushTs tnam1 bs
        return (tnam2, b' : bs')


-- | Rewrite an anonymous binder and push it on the stack.
push    :: Ord n
        => Namifier s n
        -> Bind n
        -> State s (Namifier s n, Bind n)

push nam b
 = case b of
        BAnon t
         -> do  n       <- namifierNew nam (namifierEnv nam) b
                let b'  = BName n t
                return  ( nam { namifierStack = b' : namifierStack nam
                              , namifierEnv   = Env.extend b (namifierEnv nam) }
                        , b' )

        _ ->    return  ( nam { namifierEnv   = Env.extend b (namifierEnv nam) }
                        , b)


