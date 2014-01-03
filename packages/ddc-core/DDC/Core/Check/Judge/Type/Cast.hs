
module DDC.Core.Check.Judge.Type.Cast
        (checkCast)
where
import DDC.Core.Check.Judge.Type.Base
import qualified DDC.Type.Sum   as Sum
import qualified Data.Set       as Set


checkCast :: Checker a n

-- type cast -------------------------------------
-- Weaken an effect, adding in the given terms.
checkCast !table !ctx xx@(XCast a (CastWeakenEffect eff) x1) dXX
 = do   let config      = tableConfig  table
        let kenv        = tableKindEnv table

        -- Check the effect term.
        (eff', kEff, _) <- checkTypeM config kenv ctx eff               -- TODO: use ctx

        -- Check the body.
        (x1', t1, effs, clo, ctx1)
                        <- tableCheckExp table table ctx x1 dXX

        
        -- The effect term must have Effect kind.
        when (not $ isEffectKind kEff)
         $ throw $ ErrorWeakEffNotEff a xx eff' kEff

        let c'     = CastWeakenEffect eff'
        let effs'  = Sum.insert eff' effs

        returnX a (\z -> XCast z c' x1')
                t1 effs' clo ctx1
                

-- Weaken a closure, adding in the given terms.
checkCast !table !ctx (XCast a (CastWeakenClosure xs) x1) dXX
 = do   
        -- Check the contained expressions.
        --  Just ditch the resulting contexts because they shouldn't
        --  contain expression that need types infered.
        (xs', closs, _ctx)
                <- liftM unzip3
                $ mapM (\x -> checkArgM table ctx x Recon) xs

        -- Check the body.
        (x1', t1, effs, clos, ctx1)
                <- tableCheckExp table table ctx x1 dXX
        
        let c'     = CastWeakenClosure xs'
        let closs' = Set.unions (clos : closs)

        returnX a (\z -> XCast z c' x1')
                t1 effs closs' ctx1


-- Purify an effect, given a witness that it is pure.
checkCast !table !ctx xx@(XCast a (CastPurify w) x1) dXX
 = do   let config      = tableConfig table
        let kenv        = tableKindEnv table
        let tenv        = tableTypeEnv table

        -- Check the witness.
        (w', tW)  <- checkWitnessM config kenv tenv ctx w
        let wTEC  = reannotate fromAnT w'

        -- Check the body.
        (x1', t1, effs, clo, ctx1)
                  <- tableCheckExp table table ctx x1 dXX

        -- The witness must have type (Pure e), for some effect e.
        effs' <- case tW of
                  TApp (TCon (TyConWitness TwConPure)) effMask
                    -> return $ Sum.delete effMask effs
                  _ -> throw  $ ErrorWitnessNotPurity a xx w tW

        let c'  = CastPurify wTEC

        returnX a (\z -> XCast z c' x1')
                t1 effs' clo ctx1


-- Forget a closure, given a witness that it is empty.
checkCast !table !ctx xx@(XCast a (CastForget w) x1) dXX
 = do   let config      = tableConfig table
        let kenv        = tableKindEnv table
        let tenv        = tableTypeEnv table

        -- Check the witness.
        (w', tW)  <- checkWitnessM config kenv tenv ctx w
        let wTEC  = reannotate fromAnT w'

        -- Check the body.
        (x1', t1, effs, clos, ctx1)  
                  <- tableCheckExp table table ctx x1 dXX

        -- The witness must have type (Empty c), for some closure c.
        clos' <- case tW of
                  TApp (TCon (TyConWitness TwConEmpty)) cloMask
                    -> return $ maskFromTaggedSet 
                                        (Sum.singleton kClosure cloMask)
                                        clos

                  _ -> throw $ ErrorWitnessNotEmpty a xx w tW

        let c'  = CastForget wTEC

        returnX a (\z -> XCast z c' x1')
                t1 effs clos' ctx1


-- Box a computation,
-- capturing its effects in a computation type.
checkCast !table ctx (XCast a CastBox x1) _
 = do   
        -- Check the body.
        (x1', t1, effs, clos, ctx1) 
                <- tableCheckExp table table ctx x1 Recon

        -- The result type is (S effs a),
        --  where effs is the type of the body.
        let tS  = tApps (TCon (TyConSpec TcConSusp))
                        [TSum effs, t1]

        returnX a (\z -> XCast z CastBox x1')
                tS (Sum.empty kEffect) clos ctx1


-- Run a suspended computation,
-- releasing its effects into the environment.
checkCast !table !ctx xx@(XCast a CastRun x1) _
 = do   
        let config      = tableConfig table

        -- Check the body.
        (x1', t1, effs, clos, ctx1) 
                <- tableCheckExp table table ctx x1 Recon

        -- The body must have type (S eff a),
        --  and the result has type 'a' while unleashing effect 'eff'.
        case t1 of
         TApp (TApp (TCon (TyConSpec TcConSusp)) eff2) tA 
          -> do
                -- Check that the context has the capability to support 
                -- this effect.
                checkEffectSupported config a xx ctx eff2

                ctrace  $ vcat 
                        [ text "* Run"
                        , text "  eff = " <> ppr eff2
                        , text "  t   = " <> ppr tA
                        , indent 2 $ ppr ctx 
                        , empty ]

                returnX a
                        (\z -> XCast z CastRun x1')
                        tA 
                        (Sum.union effs (Sum.singleton kEffect eff2))
                        clos
                        ctx1

         _ -> throw $ ErrorRunNotSuspension a xx t1

checkCast _ _ _ _
        = error "ddc-core.checkCast: no match"


-- Arg ------------------------------------------------------------------------
-- | Like `checkExp` but we allow naked types and witnesses.
checkArgM 
        :: (Show n, Pretty n, Ord n)
        => Table a n            -- ^ Static config.
        -> Context n            -- ^ Input context.
        -> Exp a n              -- ^ Expression to check.
        -> Mode n               -- ^ Checking mode.
        -> CheckM a n 
                ( Exp (AnTEC a n) n
                , Set (TaggedClosure n)
                , Context n)

checkArgM !table !ctx !xx !dXX
 = let  tenv    = tableTypeEnv table
        kenv    = tableKindEnv table
   in case xx of
        XType a t
         -> do  (t', k, _) <- checkTypeM (tableConfig table) kenv ctx t         -- TODO: use ctx
                let Just clo = taggedClosureOfTyArg kenv ctx t
                let a'   = AnTEC k (tBot kEffect) (tBot kClosure) a
                return  ( XType a' t'
                        , clo
                        , ctx)

        XWitness a w
         -> do  (w', t)  <- checkWitnessM (tableConfig table) kenv tenv ctx w
                let a'   = AnTEC t (tBot kEffect) (tBot kClosure) a
                return  ( XWitness a' (reannotate fromAnT w')
                        , Set.empty
                        , ctx)

        _ -> do
                (xx', _, _, clos, ctx') 
                        <- tableCheckExp table table ctx xx dXX
                return  (xx', clos, ctx')
                        

-- Support --------------------------------------------------------------------
checkEffectSupported 
        :: Ord n 
        => Config n 
        -> a
        -> Exp a n
        -> Context n 
        -> Effect n 
        -> CheckM a n ()

checkEffectSupported _config a xx ctx eff
 = case effectSupported eff ctx of
        Nothing         -> return ()
        Just effBad     -> throw $ ErrorRunNotSupported a xx effBad
 
