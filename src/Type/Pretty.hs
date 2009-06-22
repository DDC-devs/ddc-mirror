{-# OPTIONS -fwarn-incomplete-patterns #-}

-- | Pretty printer for type expressions.
module Type.Pretty
	( prettyTB
	, prettyVK
	, prettyTypeSplit
	, prettyTS)

where

import Type.Exp
import Type.Util.Bits
import Shared.Pretty
import Shared.Error
import qualified Shared.Var	as Var
import Shared.Var		(NameSpace(..))
import Util

-----
stage	= "Type.Pretty"

-- Bind -------------------------------------------------------------------------------------------
instance Pretty Bind PMode where
 ppr xx
  = case xx of
  	BVar v		-> ppr v
	BMore v t	-> "(" % v % " :> " % t % ")"

-- Type --------------------------------------------------------------------------------------------
instance Pretty Type PMode where
 ppr xx
  = case xx of
 	TNil		-> ppr "@TNil"

	TForall b k t	
	 -> let	(bks, tBody) = slurpTForall xx
	    in	"forall " % punc " " (map (uncurry pprBindKind) bks) % ". " % tBody

	TContext c t	-> c % " => " % t
	TFetters t fs	-> t % " :- " % ", " %!% fs
	TSum k  es	-> k  % "{" % "; " %!% es % "}"
	TMask k  t1 t2	-> prettyTB t1 % " \\ " % prettyTB t2

	TApp t1 t2
	 -> let result
	 		| Just (t1, t2, eff, clo)	<- takeTFun xx
			= case (eff, clo) of
			 	(TBot KEffect, 	TBot KClosure)	
				 -> prettyTBF t1 % " -> " % prettyTRight t2

				(eff,   	TBot KClosure)	
				 -> prettyTBF t1 % " -(" % eff % ")> " % prettyTRight t2
		
				(TBot KEffect,	clo)		
				 -> prettyTBF t1 % " -(" % clo % ")> " % prettyTRight t2

				(eff,   	clo)		
				 -> prettyTBF t1 % " -(" % prettyTB eff % " " % prettyTB clo % ")> " % prettyTRight t2

			| otherwise
			= let	pprAppLeft x 
			 	  | isTApp x 	= ppr x
				  | otherwise		= prettyTB x

				pprAppRight x
				  | isSomeTVar x 
				  = ppr x

				  | otherwise		
				  = prettyTB x

			 in	pprAppLeft t1 % " " % pprAppRight t2
	   in result


	TCon tycon	-> ppr tycon

	TVar k v	-> pprVarKind v k 

	TTop k		-> k % "Top"
	TBot k		-> k % "Bot"

	-- data
	TData k v []	-> pprVarKind v k
	TData k v ts	-> pprVarKind v k <> " " %!% (map prettyTB ts)

	TFun t1 t2 eff clo
	 -> case (eff, clo) of
	 	(TBot _ ,	TBot _)	-> prettyTBF t1 % " -> " % prettyTRight t2
		(eff',		TBot _)	-> prettyTBF t1 % " -(" % eff' % ")> " % prettyTRight t2
		(TBot _,	clo')	-> prettyTBF t1 % " -(" % clo' % ")> " % prettyTRight t2
		(eff',		clo')	-> prettyTBF t1 % " -(" % prettyTB eff' % " " % prettyTB clo' % ")> " 
								% prettyTRight t2
		
	-- effect
	TEffect    v []	-> ppr v
	TEffect    v ts	-> v % " " % " " %!% map prettyTB ts

	-- closure
	TFree  v t	-> v % " : " % t
	TDanger v t	-> v % " $> " % t
	TTag v		-> ppr v
	
	-- wild cards
	TWild k		-> k % "_"

	-- used in type inference
	TClass k c
	 -> case k of	
	 	KFun{}	-> parens k % c
		_	-> k % c

	TFetter f	-> "@TFetter " % f
	TError k t	-> "@TError" % k % " " % t

	-- type elaboration in source
	TElaborate elab t -> prettyTB t % "{" % elab % "}"

	-- core stuff
	TVarMore k v t
	 -> ifMode (elem PrettyCoreMore)
	 	(case k of
		 	KValue	-> parens $ "*" % v % " :> " % t 
			_	-> parens $ v % " :> " % t)
			
		(case k of
		 	KValue	-> "*" % v
			_	-> ppr v)

	TWitJoin wits		-> "wjoin {" % "; " %!% wits % "}"

	TIndex ix
	 -> parens $ ppr ix

prettyTRight tt
 = case tt of
 	TFetters{}	-> "(" % tt % ")"
	_		-> ppr tt


prettyTBF t
	| Just{}	<- takeTFun t
	=  "(" % t % ")"

	| otherwise
	= ppr t


prettyTB t
 = case t of
 	TData k v []	-> ppr t
	TVar k v 	-> ppr t
	TSum{}		-> ppr t
	TEffect v []	-> ppr t
	TTag v		-> ppr t
	TWild{}		-> ppr t
	TClass{}	-> ppr t
	TBot{}		-> ppr t
	TTop{}		-> ppr t
	TCon{}		-> ppr t
	_		-> "(" % t % ")"


pprVarKind :: Var -> Kind -> PrettyM PMode
pprVarKind v k
 = ifMode 
 	(elem PrettyTypeKinds)
	(if kindOfSpace2 v (Var.nameSpace v) == k
		then ppr v
		else "(" % ppr v % " :: " % k % ")")

	(ppr v)

pprBindKind :: Bind -> Kind -> PrettyM PMode
pprBindKind bb k
 = case bb of
 	BVar v		-> pprVarKind v k
	BMore v t	-> pprVarKind v k % " :> " % t
	

-- | Get the kind associated with a namespace.
--	This is a local local copy to avoid module recursion.
--	Also in Type.Util.Bits
kindOfSpace2 :: Var -> NameSpace -> Kind
kindOfSpace2 var space
 = case space of
 	NameType	-> KValue
	NameRegion	-> KRegion
	NameEffect	-> KEffect
	NameClosure	-> KClosure
	NameClass	-> KFetter	
	_		-> freakout stage
				("kindOfSpace2: no match for " % show space % "\n"
				% "   var = " % show var % "\n")
				KNil


-- | Prints a type with the fetters on their own lines
prettyTypeSplit :: Type	-> PrettyM PMode
prettyTypeSplit	   tt
 = case tt of
 	TForall b k t
	 -> let (bks, tBody)	= slurpTForall tt
	    in	"forall " % punc " " (map (uncurry pprBindKind) bks) % "\n"
	    		% ".  " % prettyTypeSplit2 tBody
	 
	t -> prettyTypeSplit2 t
	 
prettyTypeSplit2 x
 = case x of
 	TFetters t fs
	 -> t 	% "\n"
	 % ":- " % prettyTypeFS fs
	
	_ -> ppr x
	 
prettyTypeFS fs
 	= "\n,  " %!% fs
		
prettyTS t
	= prettyTypeSplit t 


-- | Prints a variable with an optional kind.
prettyVK :: Var -> Kind -> PrettyM PMode
prettyVK v k
 = ifMode (elem PrettyTypeKinds)
 	(parens $ v % " :: " % k)
	(ppr v)

prettyTyClassK :: TyClass -> Kind -> PrettyM PMode
prettyTyClassK tc k
 = ifMode (elem PrettyTypeKinds)
 	(parens $ ppr tc % " :: " % k)
	(ppr tc)

-- Elaboration -------------------------------------------------------------------------------------
instance Pretty Elaboration PMode where
 ppr ee
  = case ee of
	ElabRead	-> ppr "read"
	ElabWrite	-> ppr "write"
	ElabModify	-> ppr "modify"
	


-- TyCon -------------------------------------------------------------------------------------------
instance Pretty TyCon PMode where
 ppr p
  = case p of
  	TyConFun{}		-> ppr "(->)"

	TyConData 
	 { tyConName, tyConDataKind }	
	 	-> prettyVK tyConName (tyConDataKind)

	TyConClass 
	 { tyConClass, tyConClassKind}	
		-> prettyTyClassK tyConClass tyConClassKind

-- TyClass -----------------------------------------------------------------------------------------
instance Pretty TyClass PMode where
 ppr cc
  = case cc of
  	TyClassConst	-> ppr "Const"
	TyClassConstT	-> ppr "ConstT"
	TyClassMutable	-> ppr "Mutable"
	TyClassMutableT	-> ppr "MutableT"
	TyClassLazy	-> ppr "Lazy"
	TyClassLazyH	-> ppr "LazyH"
	TyClassDirect	-> ppr "Direct"
	TyClassPurify	-> ppr "Purify"
	TyClassPure	-> ppr "Pure"
	TyClassEmpty	-> ppr "Empty"
	TyClass var	-> ppr var

-- TProj -------------------------------------------------------------------------------------------
instance Pretty TProj PMode where
 ppr p
  = case p of
  	TJField  v	-> "." % v
	TJFieldR v	-> "#" % v
	_		-> panic stage "ppr[TProj]: no match"


-- ClassId -----------------------------------------------------------------------------------------
instance Pretty ClassId PMode where
 ppr c
  = case c of
  	ClassId i	-> ppr i

-- Fetter ------------------------------------------------------------------------------------------
instance Pretty Fetter PMode where
 ppr f
  = case f of
  	FConstraint	c ts	-> c  % " " % " " %!% map prettyTB ts
	FWhere		t1 t2	-> padL 10 t1 % " = "	% t2
	FMore		t1 t2	-> padL 10 t1 % " :> " % t2

	FProj     pj v1 tDict tBind
	 -> "Proj "	% pj	% " " % v1 % " " % tDict % " " % tBind


-- Kind --------------------------------------------------------------------------------------------
instance Pretty Kind PMode where
 ppr k
  = case k of
	KNil		-> ppr "?"

	KFun k1 k2	-> k1 % " -> " % k2
	KForall k1 k2	-> "\\" % k1 % ". " % k2

	KValue		-> ppr "*"
	KRegion		-> ppr "%"
	KEffect		-> ppr "!"
	KFetter		-> ppr"+"
	KClosure	-> ppr "$"

  	KClass v ts	-> v % " " % " " %!% map prettyTB ts
	KWitJoin ks	-> "join " % "{" % punc "; " ks % "}"


-- InstanceInfo ------------------------------------------------------------------------------------
instance  (Pretty param PMode)
	=> Pretty (InstanceInfo param Type) PMode where
 ppr ii
  = case ii of
  	InstanceLambda v1 v2 mt
	 -> "InstanceLambda " 	% v1 % " " % v2 % " " % mt

	InstanceLet    v1 v2 ts	t 
	 -> "InstanceLet\n" 	
	 	% "    use var     = " % v1 % "\n"
		% "    binding var = " % v2 % "\n\n"
		% "    type parameters:\n"
			%> ("\n" %!% ts) % "\n\n"
		% "    scheme:\n"
			%>  (prettyTS t)
		% "\n\n"

	InstanceLetRec v1 v2 mt
	 -> "InstanceLetRec "	% v1 % " " % v2 % " " % mt



