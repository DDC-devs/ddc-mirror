
module DDC.Type.Exp.Pretty where
import DDC.Type.Exp.TyCon
import DDC.Data.Pretty
import qualified Data.Text      as Text

instance Pretty SoCon where
 ppr sc 
  = case sc of
        SoConComp       -> text "Comp"
        SoConProp       -> text "Prop"


instance Pretty KiCon where
 ppr kc
  = case kc of
        KiConFun        -> text "(->)"
        KiConData       -> text "Data"
        KiConRegion     -> text "Region"
        KiConEffect     -> text "Effect"
        KiConClosure    -> text "Closure"
        KiConWitness    -> text "Witness"


instance Pretty TwCon where
 ppr tw
  = case tw of
        TwConImpl       -> text "(=>)"
        TwConPure       -> text "Purify"
        TwConConst      -> text "Const"
        TwConDeepConst  -> text "DeepConst"
        TwConMutable    -> text "Mutable"
        TwConDeepMutable-> text "DeepMutable"
        TwConDistinct n -> text "Distinct" <> ppr n
        TwConDisjoint   -> text "Disjoint"
        

instance Pretty TcCon where
 ppr tc 
  = case tc of
        TcConUnit        -> text "Unit"
        TcConSusp        -> text "S"
        TcConFunExplicit -> text "(->)"
        TcConFunImplicit -> text "(~>)"

        TcConRecord nn  
         -> text "(" 
         <> (hcat $ punctuate (text ",") $ map (text . Text.unpack) nn) 
         <> text ")#"

        TcConRead        -> text "Read"
        TcConHeadRead    -> text "HeadRead"
        TcConDeepRead    -> text "DeepRead"
        TcConWrite       -> text "Write"
        TcConDeepWrite   -> text "DeepWrite"
        TcConAlloc       -> text "Alloc"
        TcConDeepAlloc   -> text "DeepAlloc"

