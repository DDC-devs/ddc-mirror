
module Core.Util.Slurp
	( maybeSlurpTypeX
	, slurpTypesP
	, slurpTypeMapPs
	, slurpSuperMapPs
	, slurpCtorDefs 
	, slurpExpX
	, slurpEffsX
	, slurpBoundVarsP
	, slurpBoundVarsS 
	
	, dropXTau)

where

import qualified Data.Map	as Map
import Data.Map			(Map)

import Util
import Shared.Error
import Core.Exp
import Core.Util.Pack
import Core.Util.Bits
import Core.Pretty

-----
stage	= "Core.Util.Slurp"

-----
maybeSlurpTypeX :: Exp -> Maybe Type
maybeSlurpTypeX	xx
	| XAnnot n x		<- xx
	, Just t		<- maybeSlurpTypeX x
	= Just t

	| XLAM v k@(KClass{}) x	<- xx
	, Just x'		<- maybeSlurpTypeX x
	= Just $ TContext k x'

 	| XLAM v k x		<- xx
	, Just x'		<- maybeSlurpTypeX x
	= Just $ TForall v k x'
	
	| XLam v t x eff clo	<- xx
	, Just x'		<- maybeSlurpTypeX x
	= Just $ TFunEC t x' eff clo
	
	| XTet vts x		<- xx
	, Just x'		<- maybeSlurpTypeX x
	= Just $ TWhere x' vts

	| XTau t x		<- xx
	= Just t

	| XDo ss		<- xx
	, Just sLast		<- takeLast ss
	= maybeSlurpTypeS sLast

	| XMatch aa eff		<- xx
	, Just aLast		<- takeLast aa
	= maybeSlurpTypeA aLast
	
	| XConst c t		<- xx
	= Just t
	
	| XPrim (MFun v tR) aa	 eff	<- xx
	= Just tR
	
	| XPrim (MBox tB tU) x	 eff	<- xx
	= Just tB
	
	| XPrim (MUnbox tU tB) x eff	<- xx
	= Just tU
	
	
	| otherwise
	= Nothing


maybeSlurpTypeA :: Alt -> Maybe Type
maybeSlurpTypeA (AAlt gs x)	= maybeSlurpTypeX x

maybeSlurpTypeS :: Stmt -> Maybe Type
maybeSlurpTypeS (SBind mV x)	= maybeSlurpTypeX x




-- | Slurp off the types of the bindings defined by this top level thing
slurpTypesP :: Top -> [(Var, Type)]
slurpTypesP pp
 = case pp of
	PExtern v tv to	-> [(v, tv)]
	PCtor   v tv to	-> [(v, tv)]
	PBind   v x
	 -> case maybeSlurpTypeX x of
	 	Just t	-> [(v, t)]
		Nothing	-> panic stage
			$ "Core.Util.Slurp: slurpTypesP\n"
			% "  can't get type from this top-level thing\n"
			% pp % "\n\n"

	PClassDict v ts context sigs -> sigs
	_ -> []


-----
slurpTypeMapPs ::	[Top] -> Map Var Type
slurpTypeMapPs ps
 	= Map.fromList
	$ catMap slurpTypesP ps
	
	
-----
slurpSuperMapPs ::	[Top] -> Map Var Top
slurpSuperMapPs	ps
	= Map.fromList
	$ [ (v, p) | p@(PBind v _) <- ps]


	

-----
slurpExpX ::	Exp -> Exp
slurpExpX xx
 = case xx of
 	XLAM 	v k x	-> slurpExpX x
	XTet 	vts x	-> slurpExpX x
	XTau 	t x	-> slurpExpX x
	_		-> xx


-----
slurpEffsX ::	Exp -> Effect
slurpEffsX xx	
	= makeTSum KEffect 
	$ slurpEffsX' xx
	
slurpEffsX'	xx
 = case xx of
	XAnnot n x		-> slurpEffsX' x

 	XLAM v k x		-> slurpEffsX' x
	XAPP x t		-> slurpEffsX' x

	XLam v t x eff c	-> []
	XApp x1 x2 eff		-> [eff] ++ slurpEffsX' x1 ++ slurpEffsX' x2
	
	XTet vts x		-> slurpEffsX' x
	XTau  t x		-> slurpEffsX' x
	
	XDo _			-> [TNil]
	XMatch aa eff		-> [eff]
	XConst{}		-> []
	XVar{}			-> []

	XPrim m xx eff		-> [eff]
	XLocal v vs x		-> slurpEffsX' x
	
	-- atoms
	XAtom v xx		-> []
	
	
	_ -> panic stage
		$ "slurpEffsX': no match for " % show xx	

slurpCtorDefs :: Tree -> Map Var CtorDef
slurpCtorDefs tree
 	= Map.fromList
	$ [ (vCtor, c)	| PData vData vs ctors		<- tree 
			, c@(CtorDef vCtor fields)	<- ctors ]
-----
slurpBoundVarsP
	:: Top -> [Var]
	
slurpBoundVarsP pp
 = case pp of
	PNil				-> []
 	PBind   v x			-> [v]
	PExtern v t1 t2			-> [v]
	PData 	v vs ctors		-> v : [c | CtorDef c fs <- ctors]
	PCtor	v t1 t2			-> [v]

	PClassDict v ts contest vts	-> map fst vts
	PClassInst{}			-> []

	PRegion v			-> [v]
	PEffect	v k			-> [v]
	PClass 	v k			-> [v]
	
-----
slurpBoundVarsS
	:: Stmt -> [Var]

slurpBoundVarsS ss
 = case ss of
	SBind (Just v) x	-> [v]
	_			-> []




-- | Decend into this expression and annotate the first value found with its type
--	doing this makes it possible to slurpType this expression
--
dropXTau :: Exp -> Map Var Type -> Type -> Exp
dropXTau xx env tt
	-- load up bindings into the environment
	| TWhere t vts		<- tt
	= dropXTau xx (Map.union (Map.fromList vts) env) t

	-- decend into XLAMs
	| XLAM v t x		<- xx
	, TForall v t1 t2	<- tt
	= XLAM v t $ dropXTau x env t2
	
	| XLAM v t x		<- xx
	, TContext t1 t2	<- tt
	= XLAM v t $ dropXTau x env t2
	
	-- decend into XLams
	| XLam v t x eff clo	<- xx
	, TFunEC _ t2 _ _	<- tt
	= XLam v t (dropXTau x env t2) eff clo
	
	-- If we see an XTet on the way down then we won't need to give a TWhere
	--	for that binding, it'll already be in scope.
	| XTet vts x		<- xx
	= XTet vts $ dropXTau x (foldr Map.delete env $ map fst vts) tt

	-- there's already an XTau here,
	--	no point adding another one, 
	--	bail out
	| XTau t x		<- xx
	= xx
	
	-- we've hit a value, drop the annot
	| otherwise
	= XTau (packT $ makeTWhere tt (Map.toList env)) xx
