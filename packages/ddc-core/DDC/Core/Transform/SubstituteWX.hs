
-- | Capture avoiding substitution of witnesses in expressions.
--
--   If a binder would capture a variable then it is anonymized
--   to deBruijn form.
--
module DDC.Core.Transform.SubstituteWX
        ( SubstituteWX(..)
        , substituteWX
        , substituteWXs)
where
import DDC.Core.Exp.Annot.Exp
import DDC.Core.Collect
import DDC.Core.Transform.Rename
import DDC.Core.Transform.BoundX
import DDC.Type.Exp.Simple
import Data.Maybe
import qualified DDC.Type.Env   as Env
import qualified Data.Set       as Set
import Control.Monad


-- | Wrapper for `substituteWithWX` that determines the set of free names in the
--   type being substituted, and starts with an empty binder stack.
substituteWX 
        :: (Ord n, SubstituteWX c) 
        => Bind n -> Witness a n -> c a n -> c a n

substituteWX b wArg xx
 | Just u       <- takeSubstBoundOfBind b
 = substituteWithWX wArg
        ( Sub 
        { subBound      = u

          -- Rewrite level-1 binders that have the same name as any
          -- of the free variables in the expression to substitute.
        , subConflict1  
                = Set.fromList
                $  (mapMaybe takeNameOfBound $ Set.toList $ freeT Env.empty wArg) 

          -- Rewrite level-0 binders that have the same name as any
          -- of the free variables in the expression to substitute.
        , subConflict0
                = Set.fromList
                $ mapMaybe takeNameOfBound 
                $ Set.toList 
                $ freeX Env.empty wArg
                
        , subStack1     = BindStack [] [] 0 0
        , subStack0     = BindStack [] [] 0 0
        , subShadow0    = False })
        xx

 | otherwise    = xx
 

-- | Wrapper for `substituteWithWX` to substitute multiple things.
substituteWXs 
        :: (Ord n, SubstituteWX c) 
        => [(Bind n, Witness a n)] -> c a n -> c a n
substituteWXs bts x
        = foldr (uncurry substituteWX) x bts


-------------------------------------------------------------------------------
class SubstituteWX (c :: * -> * -> *) where
 substituteWithWX
        :: forall a n. Ord n
        => Witness a n -> Sub n -> c a n -> c a n


instance SubstituteWX Exp where 
 substituteWithWX wArg sub xx
  = {-# SCC substituteWithWX #-}
    let down s x   = substituteWithWX wArg s x
        into s x   = renameWith s x
    in case xx of
        XVar a u        -> XVar a u
        XCon{}          -> xx
        XApp a x1 x2    -> XApp a (down sub x1) (down sub x2)

        XLAM a b x
         -> let (sub1, b')      = bind1 sub b
                x'              = down  sub1 x
            in  XLAM a b' x'

        XLam a b x
         -> let (sub1, b')      = bind0 sub  b
                x'              = down  sub1 x
            in  XLam a b' x'

        XLet a (LLet b x1) x2
         -> let x1'             = down  sub  x1
                (sub1, b')      = bind0 sub  b
                x2'             = down  sub1 x2
            in  XLet a (LLet b' x1') x2'

        XLet a (LRec bxs) x2
         -> let (bs, xs)        = unzip  bxs
                (sub1, bs')     = bind0s sub bs
                xs'             = map (down sub1) xs
                x2'             = down sub1 x2
            in  XLet a (LRec (zip bs' xs')) x2'

        XLet a (LPrivate b mT bs) x2
         -> let (sub1, b')      = bind1s sub b
                (sub2, bs')     = bind0s sub1 bs
                x2'             = down   sub2 x2
                mT'             = liftM (into sub) mT
            in  XLet a (LPrivate b' mT' bs') x2'

        XCase    a x1 alts      -> XCase    a (down sub x1) (map (down sub) alts)
        XCast    a cc x1        -> XCast    a (down sub cc) (down sub x1)
        XType    a t            -> XType    a (into sub t)
        XWitness a w            -> XWitness a (down sub w)


instance SubstituteWX Alt where
 substituteWithWX wArg sub aa
  = let down s x = substituteWithWX wArg s x
    in case aa of
        AAlt PDefault xBody
         -> AAlt PDefault $ down sub xBody
        
        AAlt (PData uCon bs) x
         -> let (sub1, bs')     = bind0s sub bs
                x'              = down   sub1 x
            in  AAlt (PData uCon bs') x'


instance SubstituteWX Cast where
 substituteWithWX wArg sub cc
  = let down s x = substituteWithWX wArg s x
        into s x = renameWith s x
    in case cc of
        CastWeakenEffect eff    -> CastWeakenEffect  (into sub eff)
        CastPurify w            -> CastPurify        (down sub w)
        CastBox                 -> CastBox
        CastRun                 -> CastRun


instance SubstituteWX Witness where
 substituteWithWX wArg sub ww
  = let down s x = substituteWithWX wArg s x
        into s x = renameWith s x
    in case ww of
        WVar a u
         -> case substW wArg sub u of
                Left u'  -> WVar a u'
                Right w  -> w

        WCon{}                  -> ww
        WApp  a w1 w2           -> WApp  a (down sub w1) (down sub w2)
        WType a t               -> WType a (into sub t)


-- | Rewrite or substitute into a witness variable.
substW  :: Ord n => Witness a n -> Sub n -> Bound n 
        -> Either (Bound n) (Witness a n)

substW wArg sub u
  = case substBound (subStack0 sub) (subBound sub) u of
        Left  u'                -> Left u'
        Right n  
         | not $ subShadow0 sub -> Right (liftX n wArg)
         | otherwise            -> Left  u

