
module DDC.Core.Check.Exp.VarCon
        (checkVarCon)
where
import DDC.Core.Check.DaCon
import DDC.Core.Check.Exp.Base
import DDC.Core.Check.Exp.Inst
import qualified DDC.Type.Env   as Env
import qualified DDC.Type.Sum   as Sum
import qualified Data.Map       as Map
import qualified Data.Set       as Set


checkVarCon :: Checker a n

-- variables ------------------------------------
checkVarCon !table !ctx xx@(XVar a u) mode
 
 -- Look in the local context.
 | Just t       <- lookupType u ctx
 = case mode of
        -- Check subsumption against an existing type.
        -- This may instantiate existentials in the exising type.
        Check tExpect
         ->     checkSub table a ctx xx tExpect

        _ -> do ctrace  $ vcat
                        [ text "* Var Local"
                        , indent 2 $ ppr xx
                        , text "  TYPE:  " <> ppr t
                        , indent 2 $ ppr ctx 
                        , empty ]

                returnX a
                        (\z -> XVar z u)
                        t
                        (Sum.empty kEffect)
                        (Set.singleton $ taggedClosureOfValBound t u)
                        ctx

 -- Look in the global environment.
 | Just t      <- Env.lookup u (tableTypeEnv table)
 = case mode of
        -- Check subsumption against an existing type.
        -- This may instantiate existentials in the exising type.
        Check tExpect
         ->     checkSub table a ctx xx tExpect

        _ -> do ctrace  $ vcat
                        [ text "* Var Global"
                        , indent 2 $ ppr xx
                        , text "  TYPE:  " <> ppr t
                        , indent 2 $ ppr ctx
                        , empty ]

                returnX a 
                        (\z -> XVar z u)
                        t
                        (Sum.empty kEffect)
                        (Set.singleton $ taggedClosureOfValBound t u)
                        ctx
 
 -- Can't find this variable name in the environment.
 | otherwise
 = throw $ ErrorUndefinedVar a u UniverseData
         

-- constructors ---------------------------------
checkVarCon !table !ctx xx@(XCon a dc) mode
 -- For recon and synthesis we already know what type the constructor
 -- should have, so we can use that.
 | mode == Recon || mode == Synth 
 = do   let config      = tableConfig table
        let defs        = configDataDefs config

        -- All data constructors need to have valid type annotations.
        tCtor 
         <- case dc of
             DaConUnit   -> return tUnit
             
             DaConPrim{} -> return $ daConType dc

             DaConBound n
              -- Types of algebraic data ctors should be in the defs table.
              |  Just ctor <- Map.lookup n (dataDefsCtors defs)
              -> return $ typeOfDataCtor ctor

              | otherwise
              -> throw  $ ErrorUndefinedCtor a $ XCon a dc

        -- Check that the constructor is in the data type declarations.
        checkDaConM config xx a dc

        ctrace  $ vcat
                [ text "* Con"
                , indent 2 $ ppr xx
                , text "  TYPE:  " <> ppr tCtor
                , indent 2 $ ppr ctx
                , empty ]

        -- Type of the data constructor.
        returnX a
                (\z -> XCon z dc)
                tCtor
                (Sum.empty kEffect)
                Set.empty
                ctx

 -- Check subsumption against an existing type.
 -- This may instantiate existentials in the exising type.
 | otherwise
 , Check tExpect    <- mode
 = checkSub table a ctx xx tExpect


-- others ---------------------------------------
checkVarCon _ _ _ _
 = error "ddc-core.checkVarCon: no match"

