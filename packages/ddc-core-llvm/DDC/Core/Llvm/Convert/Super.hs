{-# LANGUAGE TypeFamilies #-}

module DDC.Core.Llvm.Convert.Super
        (convertSuper)
where
import DDC.Core.Llvm.Convert.Exp
import DDC.Core.Llvm.Convert.Type
import DDC.Core.Llvm.Convert.Context
import DDC.Core.Llvm.Convert.Base
import DDC.Llvm.Syntax
import DDC.Core.Salt.Platform
import DDC.Type.Predicates
import DDC.Base.Pretty                          hiding (align)
import qualified DDC.Type.Env                   as Env
import qualified DDC.Core.Llvm.Metadata.Tbaa    as Tbaa
import qualified DDC.Core.Salt                  as A
import qualified DDC.Core.Salt.Exp              as A
import qualified DDC.Core.Salt.Convert          as A
import qualified DDC.Core.Generic.Compounds     as A
import qualified DDC.Core.Module                as C
import qualified DDC.Core.Exp                   as C
import qualified Data.Set                       as Set
import qualified Data.Sequence                  as Seq
import qualified Data.Foldable                  as Seq


-- | Convert a top-level supercombinator to a LLVM function.
--   Region variables are completely stripped out.
convertSuper
        :: Context
        -> C.Bind   A.Name      -- ^ Bind of the top-level super.
        -> A.Exp                -- ^ Super body.
        -> ConvertM (Function, [MDecl])

convertSuper ctx (C.BName nSuper tSuper) x
 | Just (asParam, xBody)  <- A.takeXAbs x
 = do   
        let pp          = contextPlatform ctx
        let mm          = contextModule   ctx
        let kenv        = contextKindEnv  ctx

        -- Names of exported values.
        let nsExports   = Set.fromList $ map fst $ C.moduleExportValues mm

        -- Sanitise the super name so we can use it as a symbol
        -- in the object code.
        let Just nSuper' = A.seaNameOfSuper
                                (lookup nSuper (C.moduleImportValues mm))
                                (lookup nSuper (C.moduleExportValues mm))
                                nSuper

        -- Add parameters to environments.
        let asParam'     = eraseWitBinds asParam
        let bsParamType  = [b | A.ALAM b <- asParam']
        let bsParamValue = [b | A.ALam b <- asParam']

        mdsup     <- Tbaa.deriveMD (renderPlain nSuper') x
        let ctx'  = ctx
                  { contextKindEnv = Env.extends bsParamType  $ contextKindEnv ctx
                  , contextMDSuper = mdsup }

        -- TODO: The orginal parameters did not nessesarally have all the types
        --       occurring first, but this assumes they do. If they're out of
        --       order then we'll convert some types of binders in the wrong
        --       kind environments.
        (ctx'', vsParamValue')
                  <- bindLocalBs ctx' bsParamValue 

        -- Convert function body to basic blocks.
        label     <- newUniqueLabel "entry"
        blocks    <- convertBody ctx'' ExpTop Seq.empty label Seq.empty xBody

        -- Split off the argument and result types of the super.
        (tsParam, tResult)   
                  <- convertSuperType pp kenv tSuper
  
        -- Make parameter binders.
        let align = AlignBytes (platformAlignBytes pp)

        -- Declaration of the super.
        let decl 
                = FunctionDecl 
                { declName              = renderPlain nSuper'

                  -- Set internal linkage for non-exported functions so that they
                  -- they won't conflict with functions of the same name that
                  -- might be defined in other modules.
                , declLinkage           = if Set.member nSuper nsExports
                                                then External
                                                else Internal

                  -- ISSUE #266: Tailcall optimisation doesn't work for exported functions.
                  --   Using fast calls for non-exported functions enables the
                  --   LLVM tailcall optimisation. We can't enable this for exported
                  --   functions as well because we don't distinguish between DDC
                  --   generated functions and functions from the C libararies in 
                  --   our import specifications. We need a proper FFI system so that
                  --   we can get tailcalls for exported functions as well.
                , declCallConv          = if Set.member nSuper nsExports
                                                then CC_Ccc
                                                else CC_Fastcc

                , declReturnType        = tResult
                , declParamListType     = FixedArgs
                , declParams            = [Param t [] | t <- tsParam]
                , declAlign             = align }

        let Just ssParamValues
                = sequence
                $ map (\v -> case v of 
                                (Var (NameLocal s) _) -> Just s
                                _                     -> Nothing)
                $ vsParamValue'


        -- Build the function.
        return  ( Function
                  { funDecl     = decl
                  , funParams   = ssParamValues
                  , funAttrs    = [] 
                  , funSection  = SectionAuto
                  , funBlocks   = Seq.toList blocks }
                , Tbaa.decls mdsup ) 

convertSuper _ b x
        = throw $ ErrorInvalidSuper b x


---------------------------------------------------------------------------------------------------
-- | Erase witness bindings
eraseWitBinds :: [A.GAbs A.Name] -> [A.GAbs A.Name]
eraseWitBinds
 = let 
        isBindWit (A.ALAM _) = False
        isBindWit (A.ALam b) 
          = case b of
                 C.BName _ t | isWitnessType t -> True
                 _                             -> False

   in  filter (not . isBindWit)

