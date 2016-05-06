
module DDC.Core.Transform.SpreadX
        (SpreadX(..))
where
import DDC.Core.Module
import DDC.Core.Exp.Annot
import DDC.Type.Transform.SpreadT
import Control.Monad
import DDC.Type.Env                     (Env)
import qualified DDC.Type.Env           as Env


class SpreadX (c :: * -> *) where

 -- | Spread type annotations from binders and the environment into bound
 --   occurrences of variables and constructors.
 --
 --   Also convert `Bound`s to `UPrim` form if the environment says that
 --   they are primitive.
 spreadX :: forall n. Ord n
         => Env n -> Env n -> c n -> c n


---------------------------------------------------------------------------------------------------
instance SpreadX (Module a) where
 spreadX kenv tenv mm@ModuleCore{}
  = let liftSnd f (x, y) = (x, f y)
    in  ModuleCore
        { moduleName            
                = moduleName mm

        , moduleIsHeader        
                = moduleIsHeader mm

        , moduleExportTypes     
                = map (liftSnd $ spreadT kenv)
                $ moduleExportTypes mm

        , moduleExportValues    
                = map (liftSnd $ spreadT kenv)
                $ moduleExportValues mm
          
        , moduleImportTypes     
                = map (liftSnd $ spreadX kenv tenv) 
                $ moduleImportTypes mm

        , moduleImportCaps
                = map (liftSnd $ spreadX kenv tenv)
                $ moduleImportCaps mm

        , moduleImportValues    
                = map (liftSnd $ spreadX kenv tenv) 
                $ moduleImportValues mm

        , moduleImportDataDefs  
                = map (spreadT kenv)
                $ moduleImportDataDefs mm

        , moduleDataDefsLocal   
                = map (spreadT kenv)
                $ moduleDataDefsLocal mm
  
        , moduleBody           
                 = spreadX kenv tenv
                 $ moduleBody mm 
        }


---------------------------------------------------------------------------------------------------
instance SpreadT ExportSource where
 spreadT kenv esrc
  = case esrc of
        ExportSourceLocal n t   
         -> ExportSourceLocal n (spreadT kenv t)

        ExportSourceLocalNoType n
         -> ExportSourceLocalNoType n


---------------------------------------------------------------------------------------------------
instance SpreadX ImportType where
 spreadX kenv _tenv isrc
  = case isrc of
        ImportTypeAbstract t
         -> ImportTypeAbstract (spreadT kenv t)

        ImportTypeBoxed t
         -> ImportTypeBoxed    (spreadT kenv t)


---------------------------------------------------------------------------------------------------
instance SpreadX ImportCap where
 spreadX kenv _tenv isrc
  = case isrc of
        ImportCapAbstract t
         -> ImportCapAbstract   (spreadT kenv t)


---------------------------------------------------------------------------------------------------
instance SpreadX ImportValue where
 spreadX kenv _tenv isrc
  = case isrc of
        ImportValueModule mn n t mArity
         -> ImportValueModule   mn n (spreadT kenv t) mArity

        ImportValueSea n t
         -> ImportValueSea n    (spreadT kenv t)


---------------------------------------------------------------------------------------------------
instance SpreadX (Exp a) where
 spreadX kenv tenv xx 
  = {-# SCC spreadX #-}
    let down x = spreadX kenv tenv x
    in case xx of
        XVar a u        -> XVar a (down u)
        XCon a d        -> XCon a (spreadDaCon kenv tenv d)
        XApp a x1 x2    -> XApp a (down x1) (down x2)

        XLAM a b x
         -> let b'      = spreadT kenv b
            in  XLAM a b' (spreadX (Env.extend b' kenv) tenv x)

        XLam a b x      
         -> let b'      = down b
            in  XLam a b' (spreadX kenv (Env.extend b' tenv) x)
            
        XLet a lts x
         -> let lts'    = down lts
                kenv'   = Env.extends (specBindsOfLets   lts') kenv
                tenv'   = Env.extends (valwitBindsOfLets lts') tenv
            in  XLet a lts' (spreadX kenv' tenv' x)
         
        XCase a x alts  -> XCase    a (down x) (map down alts)
        XCast a c x     -> XCast    a (down c) (down x)
        XType a t       -> XType    a (spreadT kenv t)
        XWitness a w    -> XWitness a (down w)


---------------------------------------------------------------------------------------------------
spreadDaCon _kenv tenv dc
  = case dc of
        DaConUnit       
         -> dc

        DaConPrim n t
         -> let u | Env.isPrim tenv n   = UPrim n t
                  | otherwise           = UName n

            in  case Env.lookup u tenv of
                 Just t' -> dc { daConType = t' }
                 Nothing -> dc

        DaConBound n
         | Env.isPrim tenv n
         , Just t'      <- Env.lookup (UPrim n (tBot kData)) tenv
         -> DaConPrim n t'

         | otherwise
         -> DaConBound n


---------------------------------------------------------------------------------------------------
instance SpreadX (Cast a) where
 spreadX kenv tenv cc
  = let down x = spreadX kenv tenv x
    in case cc of
        CastWeakenEffect eff    -> CastWeakenEffect  (spreadT kenv eff)
        CastPurify w            -> CastPurify        (down w)
        CastBox                 -> CastBox
        CastRun                 -> CastRun


---------------------------------------------------------------------------------------------------
instance SpreadX Pat where
 spreadX kenv tenv pat
  = let down x   = spreadX kenv tenv x
    in case pat of
        PDefault        -> PDefault
        PData u bs      -> PData (spreadDaCon kenv tenv u) (map down bs)


---------------------------------------------------------------------------------------------------
instance SpreadX (Alt a) where
 spreadX kenv tenv alt
  = case alt of
        AAlt p x
         -> let p'       = spreadX kenv tenv p
                tenv'    = Env.extends (bindsOfPat p') tenv
            in  AAlt p' (spreadX kenv tenv' x)


---------------------------------------------------------------------------------------------------
instance SpreadX (Lets a) where
 spreadX kenv tenv lts
  = let down x = spreadX kenv tenv x
    in case lts of
        LLet b x         
         -> LLet (down b) (down x)
        
        LRec bxs
         -> let (bs, xs) = unzip bxs
                bs'      = map (spreadX kenv tenv) bs
                tenv'    = Env.extends bs' tenv
                xs'      = map (spreadX kenv tenv') xs
             in LRec (zip bs' xs')

        LPrivate b mT bs
         -> let b'       = map (spreadT kenv) b
                mT'      = liftM (spreadT kenv) mT
                kenv'    = Env.extends b' kenv
                bs'      = map (spreadX kenv' tenv) bs
            in  LPrivate b' mT' bs'


---------------------------------------------------------------------------------------------------
instance SpreadX (Witness a) where
 spreadX kenv tenv ww
  = let down = spreadX kenv tenv 
    in case ww of
        WCon  a wc       -> WCon  a (down wc)
        WVar  a u        -> WVar  a (down u)
        WApp  a w1 w2    -> WApp  a (down w1) (down w2)
        WType a t1       -> WType a (spreadT kenv t1)


---------------------------------------------------------------------------------------------------
instance SpreadX WiCon where
 spreadX kenv tenv wc
  = case wc of
        WiConBound (UName n) _
         -> case Env.envPrimFun tenv n of
                Nothing -> wc
                Just t  
                 -> let t'      = spreadT kenv t
                    in  WiConBound (UPrim n t') t'

        _                -> wc


---------------------------------------------------------------------------------------------------
instance SpreadX Bind where
 spreadX kenv _tenv bb
  = case bb of
        BName n t        -> BName n (spreadT kenv t)
        BAnon t          -> BAnon (spreadT kenv t)
        BNone t          -> BNone (spreadT kenv t)


---------------------------------------------------------------------------------------------------
instance SpreadX Bound where
 spreadX kenv tenv uu
  | Just t'     <- Env.lookup uu tenv
  = case uu of
        UIx ix          -> UIx   ix

        UName n
         -> if Env.isPrim tenv n 
                 then UPrim n (spreadT kenv t')
                 else UName n

        UPrim n _       -> UPrim n t'

  | otherwise   = uu        

