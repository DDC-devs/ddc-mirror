
-- | Source Tetra conversion to Disciple Core Tetra language.
module DDC.Source.Tetra.Convert
        (coreOfSourceModule)
where
import qualified DDC.Source.Tetra.Transform.Guards      as S
import qualified DDC.Source.Tetra.Module                as S
import qualified DDC.Source.Tetra.DataDef               as S
import qualified DDC.Source.Tetra.Exp                   as S
import qualified DDC.Source.Tetra.Prim                  as S

import qualified DDC.Core.Tetra.Prim                    as C
import qualified DDC.Core.Compounds                     as C
import qualified DDC.Core.Module                        as C
import qualified DDC.Core.Exp                           as C
import qualified DDC.Type.DataDef                       as C

import qualified DDC.Type.Sum                           as Sum
import Data.Maybe

-- Things shared between both Source and Core languages.
import DDC.Core.Exp
        ( Bind          (..)
        , Bound         (..)
        , Type          (..)
        , TyCon         (..)
        , Pat           (..)
        , DaCon         (..)
        , Witness       (..)
        , WiCon         (..))

import DDC.Core.Module 
        ( ExportSource  (..)
        , ImportType    (..)
        , ImportValue   (..))


-- Module ---------------------------------------------------------------------
-- | Convert a Source Tetra module to Core Tetra.
--
--   The Source code needs to already have been desugared and cannot contain,
--   and `XDefix`, `XInfixOp`, or `XInfixVar` nodes, else `error`.
--
--   We use the map of core headers to add imports for all the names that this
--   module uses from its environment.
-- 
coreOfSourceModule
        :: a 
        -> S.Module a S.Name 
        -> C.Module a C.Name

coreOfSourceModule a mm
        = C.ModuleCore
        { C.moduleName          = S.moduleName mm
        , C.moduleIsHeader      = False

        , C.moduleExportTypes   
           = [ (toCoreN n, ExportSourceLocalNoType (toCoreN n))
                | n <- S.moduleExportTypes mm ]

        , C.moduleExportValues
           = [ (toCoreN n, ExportSourceLocalNoType (toCoreN n))
                | n <- S.moduleExportValues mm ]

           ++ (if C.isMainModuleName (S.moduleName mm)
                && (not $ elem (S.NameVar "main") $ S.moduleExportValues mm)
                then [ ( C.NameVar "main"
                     , ExportSourceLocalNoType (C.NameVar "main"))]
                else [])

        , C.moduleImportTypes   
           = [ (toCoreN n, toCoreImportType  isrc)
                | (n, isrc) <- S.moduleImportTypes mm ]

        , C.moduleImportValues  
           = [ (toCoreN n, toCoreImportValue isrc)
                | (n, isrc) <- S.moduleImportValues mm ]

        , C.moduleImportDataDefs
           = []
        
        , C.moduleDataDefsLocal 
           = [ toCoreDataDef def
                | S.TopData _ def <- S.moduleTops mm ]

        , C.moduleBody          
           = C.XLet  a (letsOfTops (S.moduleTops mm))
                                        (C.xUnit a) }


-- | Extract the top-level bindings from some source definitions.
letsOfTops :: [S.Top a S.Name] -> C.Lets a C.Name
letsOfTops tops
 = C.LRec $ mapMaybe bindOfTop tops


-- | Try to convert a `TopBind` to a top-level binding, 
--   or `Nothing` if it isn't one.
bindOfTop  
        :: S.Top a S.Name 
        -> Maybe (Bind C.Name, C.Exp a C.Name)

bindOfTop (S.TopBind _ b x) 
                = Just (toCoreB b, toCoreX x)
bindOfTop _     = Nothing


-- ImportType -----------------------------------------------------------------
toCoreImportType :: ImportType S.Name -> ImportType C.Name
toCoreImportType src
 = case src of
        ImportTypeAbstract t    -> ImportTypeAbstract (toCoreT t)
        ImportTypeBoxed t       -> ImportTypeBoxed (toCoreT t)


-- ImportValue ----------------------------------------------------------------
toCoreImportValue :: ImportValue S.Name -> ImportValue C.Name
toCoreImportValue src
 = case src of
        ImportValueModule mn n t mA
         -> ImportValueModule mn (toCoreN n) (toCoreT t) mA

        ImportValueSea v t    -> ImportValueSea v (toCoreT t)


-- Type -----------------------------------------------------------------------
toCoreT :: Type S.Name -> Type C.Name
toCoreT tt
 = case tt of
        TVar    u       -> TVar (toCoreU  u)
        TCon    tc      -> TCon (toCoreTC tc)        
        TForall b t     -> TForall (toCoreB b) (toCoreT t)
        TApp    t1 t2   -> TApp (toCoreT t1) (toCoreT t2)
        TSum    ts      -> TSum $ Sum.fromList (toCoreT (Sum.kindOfSum ts))
                                $ map toCoreT 
                                $ Sum.toList ts  


-- TyCon ----------------------------------------------------------------------
toCoreTC :: TyCon S.Name -> TyCon C.Name
toCoreTC tc
 = case tc of
        TyConSort sc    -> TyConSort sc
        TyConKind kc    -> TyConKind kc
        TyConWitness wc -> TyConWitness wc
        TyConSpec sc    -> TyConSpec sc
        TyConBound u k  -> TyConBound (toCoreU u) (toCoreT k)
        TyConExists n k -> TyConExists n          (toCoreT k)


-- DataDef --------------------------------------------------------------------
toCoreDataDef :: S.DataDef S.Name -> C.DataDef C.Name
toCoreDataDef def
        = C.DataDef
        { C.dataDefTypeName       
                = toCoreN     $ S.dataDefTypeName def

        , C.dataDefParams
                = map toCoreB $ S.dataDefParams def

        , C.dataDefCtors          
                = Just 
                $ [ toCoreDataCtor def tag ctor
                        | ctor  <- S.dataDefCtors def
                        | tag   <- [0..] ]

        , C.dataDefIsAlgebraic
                = True
        }


-- DataCtor -------------------------------------------------------------------
toCoreDataCtor 
        :: S.DataDef S.Name 
        -> Integer
        -> S.DataCtor S.Name 
        -> C.DataCtor C.Name

toCoreDataCtor dataDef tag ctor
        = C.DataCtor
        { C.dataCtorName        = toCoreN (S.dataCtorName ctor)
        , C.dataCtorTag         = tag
        , C.dataCtorFieldTypes  = map toCoreT (S.dataCtorFieldTypes ctor)
        , C.dataCtorResultType  = toCoreT (S.dataCtorResultType ctor)
        , C.dataCtorTypeName    = toCoreN (S.dataDefTypeName dataDef) 
        , C.dataCtorTypeParams  = map toCoreB (S.dataDefParams dataDef) }


-- Exp ------------------------------------------------------------------------
toCoreX :: S.Exp a S.Name -> C.Exp a C.Name
toCoreX xx
 = case xx of
        S.XVar     a u      -> C.XVar     a (toCoreU  u)
        S.XCon     a dc     -> C.XCon     a (toCoreDC dc)
        S.XLAM     a b x    -> C.XLAM     a (toCoreB b)  (toCoreX x)
        S.XLam     a b x    -> C.XLam     a (toCoreB b)  (toCoreX x)
        S.XApp     a x1 x2  -> C.XApp     a (toCoreX x1) (toCoreX x2)
        S.XLet     a lts x  -> C.XLet     a (toCoreLts lts) (toCoreX x)
        S.XCase    a x alts -> C.XCase    a (toCoreX x)  (map (toCoreA a) alts)
        S.XCast    a c x    -> C.XCast    a (toCoreC c)  (toCoreX x)
        S.XType    a t      -> C.XType    a (toCoreT t)
        S.XWitness a w      -> C.XWitness a (toCoreW w)

        -- These shouldn't exist in the desugared source tetra code.
        S.XDefix{}      -> error "source-tetra.toCoreX: found XDefix node"
        S.XInfixOp{}    -> error "source-tetra.toCoreX: found XInfixOp node"
        S.XInfixVar{}   -> error "source-tetra.toCoreX: found XInfixVar node"


-- Lets -----------------------------------------------------------------------
toCoreLts :: S.Lets a S.Name -> C.Lets a C.Name
toCoreLts lts
 = case lts of
        S.LLet b x
         -> C.LLet (toCoreB b) (toCoreX x)
        
        S.LRec bxs
         -> C.LRec [(toCoreB b, toCoreX x) | (b, x) <- bxs ]

        S.LPrivate bks Nothing bts
         -> C.LPrivate (map toCoreB bks) Nothing (map toCoreB bts)

        S.LPrivate bks (Just tParent) bts
         -> C.LPrivate  (map toCoreB bks) 
                        (Just $ toCoreT tParent) (map toCoreB bts)

        S.LGroup{}
         -> error "source-tetra.toCoreLts: found LGroup"


-- Cast -----------------------------------------------------------------------
toCoreC :: S.Cast a S.Name -> C.Cast a C.Name
toCoreC cc
 = case cc of
        S.CastWeakenEffect eff  -> C.CastWeakenEffect (toCoreT eff)
        S.CastPurify   w        -> C.CastPurify       (toCoreW w)
        S.CastBox               -> C.CastBox
        S.CastRun               -> C.CastRun


-- Alt ------------------------------------------------------------------------
toCoreA  :: a -> S.Alt a S.Name -> C.Alt a C.Name
toCoreA a (S.AAlt w gxs)
 = C.AAlt (toCoreP w) 
          (toCoreX (S.desugarGuards a gxs (error "toCoreA alt fail")))
                -- TODO: need pattern inexhaustiveness message.


-- Pat ------------------------------------------------------------------------
toCoreP  :: Pat S.Name -> Pat C.Name
toCoreP pp
 = case pp of
        PDefault        -> PDefault
        PData dc bs     -> PData (toCoreDC dc) (map toCoreB bs)


-- DaCon ----------------------------------------------------------------------
toCoreDC :: DaCon S.Name -> DaCon C.Name
toCoreDC dc
 = case dc of
        DaConUnit
         -> DaConUnit

        DaConPrim n t 
         -> DaConPrim
                { daConName             = toCoreN n
                , daConType             = toCoreT t }

        DaConBound n
         -> DaConBound (toCoreN n)



-- Witness --------------------------------------------------------------------
toCoreW :: Witness a S.Name -> Witness a C.Name
toCoreW ww
 = case ww of
        S.WVar  a u     -> C.WVar  a (toCoreU  u)
        S.WCon  a wc    -> C.WCon  a (toCoreWC wc)
        S.WApp  a w1 w2 -> C.WApp  a (toCoreW  w1) (toCoreW w2)
        S.WJoin a w1 w2 -> C.WJoin a (toCoreW  w1) (toCoreW w2)
        S.WType a t     -> C.WType a (toCoreT  t)


-- WiCon ----------------------------------------------------------------------
toCoreWC :: WiCon S.Name -> WiCon C.Name
toCoreWC wc
 = case wc of
        WiConBuiltin wb -> WiConBuiltin wb
        WiConBound u t  -> WiConBound (toCoreU u) (toCoreT t)


-- Bind -----------------------------------------------------------------------
toCoreB :: Bind S.Name -> Bind C.Name
toCoreB bb
 = case bb of
        BName n t       -> BName (toCoreN n) (toCoreT t)
        BAnon t         -> BAnon (toCoreT t)
        BNone t         -> BNone (toCoreT t)


-- Bound ----------------------------------------------------------------------
toCoreU :: Bound S.Name -> Bound C.Name
toCoreU uu
 = case uu of
        UName n         -> UName (toCoreN n)
        UIx   i         -> UIx   i
        UPrim n t       -> UPrim (toCoreN n) (toCoreT t)


-- Name -----------------------------------------------------------------------
toCoreN :: S.Name -> C.Name
toCoreN nn
 = case nn of
        S.NameVar        str -> C.NameVar        str
        S.NameCon        str -> C.NameCon        str
        S.NameTyConTetra tc  -> C.NameTyConTetra (toCoreTyConTetra tc)
        S.NameOpFun      tc  -> C.NameOpFun      tc
        S.NamePrimTyCon  p   -> C.NamePrimTyCon  p
        S.NamePrimArith  p   -> C.NamePrimArith  p
        S.NameLitBool    b   -> C.NameLitBool    b
        S.NameLitNat     n   -> C.NameLitNat     n
        S.NameLitInt     i   -> C.NameLitInt     i 
        S.NameLitSize    s   -> C.NameLitSize    s
        S.NameLitWord    w b -> C.NameLitWord    w b
        S.NameLitFloat   d b -> C.NameLitFloat   d b
        S.NameLitString  bs  -> C.NameLitString  bs
        S.NameHole           -> C.NameHole


toCoreTyConTetra :: S.TyConTetra -> C.TyConTetra
toCoreTyConTetra tc
 = case tc of
        S.TyConTetraTuple n  -> C.TyConTetraTuple n
        S.TyConTetraF        -> C.TyConTetraF
        S.TyConTetraC        -> C.TyConTetraC
        S.TyConTetraU        -> C.TyConTetraU
        S.TyConTetraString   -> C.TyConTetraString



        
