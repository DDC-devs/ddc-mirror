{-# LANGUAGE TypeFamilies #-}
module DDC.Llvm.Pretty.Module where
import DDC.Llvm.Syntax.Module
import DDC.Llvm.Syntax.Exp
import DDC.Llvm.Syntax.Type
import DDC.Llvm.Pretty.Function
import DDC.Llvm.Pretty.Exp      ()
import DDC.Llvm.Pretty.Metadata
import DDC.Llvm.Pretty.Base
import DDC.Data.Pretty


-------------------------------------------------------------------------------
-- | Produce a default pretty printer mode from an LLVM config.
prettyModeModuleOfConfig :: Config -> PrettyMode Module
prettyModeModuleOfConfig config
        = PrettyModeModule
        { modeModuleConfig      = config }


-------------------------------------------------------------------------------
-- | Print out a whole LLVM module.
instance Pretty Module where
 data PrettyMode Module
        = PrettyModeModule
        { modeModuleConfig      :: Config }

 pprDefaultMode
        = PrettyModeModule
        { modeModuleConfig      = defaultConfig }

 pprModePrec
        (PrettyModeModule config) prec
        (Module _comments aliases globals decls funcs mdecls)
  = let
        pprFunction' = pprModePrec (PrettyModeFunction config) prec
        pprMDecl'    = pprModePrec (PrettyModeMDecl    config) prec

    in vcat
        [  vcat $ map ppr aliases
        ,  vcat $ map ppr globals
        ,  vcat $ map (\decl -> text "declare"
                          <+> pprFunctionHeader decl Nothing) decls
        ,  mempty
        ,  vcat $ punctuate line
                $ map pprFunction' funcs
        ,  line
        ,  mempty
        ,  vcat $ map pprMDecl' mdecls
        ,  mempty ]


-------------------------------------------------------------------------------
instance Pretty Global where
 ppr gg
  = case gg of
        GlobalStatic (Var name _) static
         -> ppr name <+> text "= global" <+> ppr static

        GlobalExternal (Var name t)
         -> ppr name <+> text "= external global " <+> ppr t


-------------------------------------------------------------------------------
instance Pretty Static where
  ppr ss
   = case ss of
        StaticComment s
         -> text "; " <> text s

        StaticLit l
         -> ppr l

        StaticUninitType t
         -> ppr t <> text " undef"

        StaticStr   s t
         -> ppr t <> text " c\"" <> text s <> text "\\00\""

        StaticArray d t
         -> ppr t
         <> text " [" <> hcat (punctuate comma $ map ppr d) <> text "]"

        StaticStruct  d t
         -> ppr t
         <> text "<{" <> hcat (punctuate comma $ map ppr d) <> text "}>"

        StaticPointer (Var n t)
         -> ppr t     <> text "*" <+> ppr n

        StaticBitc v t
         -> ppr t
         <> text " bitcast"  <+> parens (ppr v <> text " to " <> ppr t)

        StaticPtoI v t
         -> ppr t
         <> text " ptrtoint" <+> parens (ppr v <> text " to " <> ppr t)

        StaticAdd s1 s2
         -> let ty1 = typeOfStatic s1
                op  = if isFloat ty1 then text " fadd (" else text " add ("
            in if ty1 == typeOfStatic s2
                then ppr ty1 <> op <> ppr s1 <> comma <> ppr s2 <> text ")"
                else error $ "ddc-core-llvm: LMAdd with different types!"

        StaticSub s1 s2
         -> let ty1 = typeOfStatic s1
                op  = if isFloat ty1 then text " fsub (" else text " sub ("
            in if ty1 == typeOfStatic s2
                then ppr ty1 <> op <> ppr s1 <> comma <> ppr s2 <> text ")"
                else error $ "ddc-core-llvm: LMSub with different types!"

