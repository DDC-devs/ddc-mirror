
-- | Constructing and checking whether rewrite rules are valid
module DDC.Core.Transform.Rewrite.Rule
        ( -- * Binding modes
          BindMode      (..)
        , isBMSpec
        , isBMValue

        , RewriteRule   (..)
        , NamedRewriteRule

          -- * Construction
        , mkRewriteRule
        , checkRewriteRule
        , Error (..)
        , Side  (..))
where
import DDC.Core.Transform.Rewrite.Error
import DDC.Core.Transform.Reannotate
import DDC.Core.Exp.Annot
import DDC.Core.Codec.Text.Pretty               ()
import DDC.Core.Env.EnvX                        (EnvX)
import DDC.Data.Pretty
import qualified DDC.Core.Analysis.Usage        as U
import qualified DDC.Core.Check                 as C
import qualified DDC.Core.Collect               as C
import qualified DDC.Type.Env                   as T
import qualified DDC.Type.Exp.Simple            as T
import qualified Data.Map                       as Map
import qualified Data.Maybe                     as Maybe
import qualified Data.Set                       as Set
import qualified DDC.Core.Env.EnvT              as EnvT
import qualified DDC.Core.Env.EnvX              as EnvX


-- | A rewrite rule. For example:
--
--   @ RULE [r1 r2 r3 : %] (x : Int r1)
--      . addInt  [:r1 r2 r3:] x (0 [r2] ()
--      = copyInt [:r1 r3:]    x
--   @
data RewriteRule a n
        = RewriteRule
        { -- | Variables bound by the rule.
          ruleBinds       :: [(BindMode, Bind n)]

          -- | Extra constraints on the rule.
          --   These must all be satisfied for the rule to fire.
        , ruleConstraints :: [Type n]

          -- | Left-hand side of the rule.
          --   We match on this part.
        , ruleLeft        :: Exp a n

          -- | Extra part of left-hand side,
          --   but allow this bit to be out-of-context.
        , ruleLeftHole    :: Maybe (Exp a n)

          -- | Right-hand side of the rule.
          --   We replace the matched expression with this part.
        , ruleRight       :: Exp a n

          -- | Effects that are caused by the left but not the right.
          --   When applying the rule we add an effect weakning to ensure
          --   the rewritten expression has the same effects.
        , ruleWeakEff     :: Maybe (Effect n)

          -- | Closure that the left has that is not present in the right.
          --   When applying the rule we add a closure weakening to ensure
          --   the rewritten expression has the same closure.
        , ruleWeakClo     :: [Exp a n]

          -- | References to environment.
          --   Used to check whether the rule is shadowed.
        , ruleFreeVars    :: [Bound n]
        } deriving (Eq, Show)


type NamedRewriteRule a n
        = (String, RewriteRule a n)


instance (Pretty n, Eq n) => Pretty (RewriteRule a n) where
 ppr (RewriteRule bs cs lhs hole rhs _ _ _)
  = pprBinders bs <> pprConstrs cs <> ppr lhs <> pprHole <> text " = " <> ppr rhs
  where pprBinders []            = text ""
        pprBinders bs'           = foldl1 (<>) (map pprBinder bs') <> text ". "

        pprBinder (BMSpec, b)    = text "[" <> ppr b <> text "] "
        pprBinder (BMValue _, b) = text "(" <> ppr b <> text ") "

        pprConstrs []            = text ""
        pprConstrs (c:cs')       = ppr c <> text " => " <> pprConstrs cs'

        pprHole
         | Just h <- hole
         = text " {" <> ppr h <> text "}"

         | otherwise
         = text ""


-- BindMode -------------------------------------------------------------------
-- | Binding level for the binders in a rewrite rule.
data BindMode
        -- | Level-1 binder (specs)
        = BMSpec

        -- | Level-0 binder (data values and witnesses)
        | BMValue Int -- ^ number of usages
        deriving (Eq, Show)


-- | Check if a `BindMode` is a `BMSpec`.
isBMSpec :: BindMode -> Bool
isBMSpec BMSpec         = True
isBMSpec _              = False


-- | Check if a `BindMode` is a `BMValue`.
isBMValue :: BindMode -> Bool
isBMValue (BMValue _)   = True
isBMValue _             = False


-- Make -----------------------------------------------------------------------
-- | Construct a rewrite rule, but do not check if it's valid.
--
--   You then need to apply 'checkRewriteRule' to check it.
--
mkRewriteRule
        :: [(BindMode,Bind n)]  -- ^ Variables bound by the rule.
        -> [Type n]             -- ^ Extra constraints on the rule.
        -> Exp a n              -- ^ Left-hand side of the rule.
        -> Maybe (Exp a n)      -- ^ Extra part of left, can be out of context.
        -> Exp a n              -- ^ Right-hand side (replacement)
        -> RewriteRule a n

mkRewriteRule  bs cs lhs hole rhs
 = RewriteRule bs cs lhs hole rhs Nothing [] []


-- Check ----------------------------------------------------------------------
-- | Take a rule, make sure it's valid and fill in type, closure and effect
--   information.
--
--   The left-hand side of rule can't have any binders (lambdas, lets etc).
--
--   All binders must appear in the left-hand side, otherwise they would match
--   with no value.
--
--   Both sides must have the same types, but the right can have fewer effects
--   and smaller closure.
--
--   We don't handle anonymous binders on either the left or right.
--
checkRewriteRule
    :: (Show a, Ord n, Show n, Pretty n)
    => C.Config n               -- ^ Type checker config.
    -> EnvX n                   -- ^ Type checker environment.
    -> RewriteRule a n          -- ^ Rule to check
    -> Either (Error a n)
              (RewriteRule (C.AnTEC a n) n)

checkRewriteRule config env
        (RewriteRule bs cs lhs hole rhs _ _ _)
 = do
        -- Extend the environments with variables bound by the rule.
        let (env', bs') = extendBinds bs env

        -- Check that all constraints are valid types.
        mapM_ (checkConstraint config) cs

        -- Typecheck, spread and annotate with type information
        (lhs', _, _)
         <- checkExp config env' Lhs lhs

        -- If the extra left part is there, typecheck and annotate it.
        hole' <- case hole of
                  Just h
                   -> do  (h',_,_)  <- checkExp config env' Lhs h
                          return $ Just h'

                  Nothing -> return Nothing

        -- Build application from lhs and the hole so we can check its
        -- type against rhs
        let a           = annotOfExp lhs
        let lhs_full    = maybe lhs (XApp a lhs) (fmap RTerm hole)

        -- Check the full left hand side.
        (lhs_full', tLeft, effLeft)
                <- checkExp config env' Lhs lhs_full

        -- Check the full right hand side.
        (rhs', tRight, effRight)
                <- checkExp config env' Rhs rhs

        -- Check that types of both sides are equivalent.
        let err = ErrorTypeConflict
                        (tLeft,  effLeft,  tBot kClosure)
                        (tRight, effRight, tBot kClosure)

        checkEquiv tLeft tRight err

        -- Check the effect of the right is smaller than that
        -- of the left, and add a weakeff cast if nessesary
        effWeak        <- makeEffectWeakening  T.kEffect effLeft effRight err

{-        -- Check that the closure of the right is smaller than that
        -- of the left, and add a weakclo cast if nessesary.
        cloWeak        <- makeClosureWeakening config env' lhs_full' rhs'
-}
        -- Check that all the bound variables are mentioned
        -- in the left-hand side.
        checkUnmentionedBinders bs' lhs_full'

        -- No BAnons allowed.
        --  We don't handle deBruijn binders.
        checkAnonymousBinders bs'

        -- No lets or lambdas in left-hand side.
        --  We can't match against these.
        checkValidPattern lhs_full

        -- Count how many times each binder is used in the right-hand side.
        bs''    <- countBinderUsage bs' rhs

        -- Get the free variables of the rule.
        let binds     = Set.fromList
                      $ Maybe.catMaybes
                      $ map (T.takeSubstBoundOfBind . snd) bs

        let freeVars  = Set.toList
                      $ (C.freeX T.empty lhs_full'
                         `Set.union` C.freeX T.empty rhs)
                      `Set.difference` binds

        return  $ RewriteRule
                        bs'' cs
                        lhs' hole' rhs'
                        effWeak []
                        freeVars


-- | Extend kind and type environments with a rule's binders.
--   Which environment a binder goes into depends on its BindMode.
--   Also return list of binders which have been spread.
extendBinds
        :: Ord n
        => [(BindMode, Bind n)]
        ->  EnvX n
        -> (EnvX n, [(BindMode, Bind n)])

extendBinds binds env0
 = go binds env0 []
 where
        go []          env acc
         = (env, acc)

        go ((bm,b):bs) env acc
         = let  env'    = case bm of
                             BMSpec    -> EnvX.extendT b env
                             BMValue _ -> EnvX.extendX b env

           in  go bs env' (acc ++ [(bm,b)])


-- | Type check the expression on one side of the rule.
checkExp
        :: (Show a, Ord n, Show n, Pretty n)
        => C.Config n   -- ^ Type checker config.
        -> EnvX n       -- ^ Type checker environment.
        -> Side         -- ^ Side that the expression appears on for errors.
        -> Exp a n      -- ^ Expression to check.
        -> Either (Error a n)
                  (Exp (C.AnTEC a n) n, Type n, Effect n)

checkExp defs env side xx
 = case C.reconOfExp defs env xx of
        Left err  -> Left $ ErrorTypeCheck side xx err
        Right rhs -> return rhs


-- | Type check a constraint on the rule.
checkConstraint
        :: (Ord n, Show n, Pretty n)
        => C.Config n
        -> Type n       -- ^ The constraint type to check.
        -> Either (Error a n) (Kind n)

checkConstraint config tt
 = case C.checkSpec config tt of
        Left _err               -> Left $ ErrorBadConstraint tt
        Right (_, k)
         | T.isWitnessType tt   -> return k
         | otherwise            -> Left $ ErrorBadConstraint tt


-- | Check equivalence of types or error
checkEquiv
        :: Ord n
        => Type n       -- ^ Type of left of rule.
        -> Type n       -- ^ Type of right of rule.
        -> Error a n    -- ^ Error to report if the types don't match.
        -> Either (Error a n) ()

checkEquiv tLeft tRight err
        | T.equivT EnvT.empty tLeft tRight
                        = return ()
        | otherwise     = Left err


-- Weaken ---------------------------------------------------------------------
-- | Make the effect weakening for a rule.
--   This contains the effects that are caused by the left of the rule
--   but not the right.
--   If the right has more effects than the left then return an error.
--
makeEffectWeakening
        :: Ord n
        => Kind n       -- ^ Should be the effect kind.
        -> Effect n     -- ^ Effect of the left of the rule.
        -> Effect n     -- ^ Effect of the right of the rule.
        -> Error a n    -- ^ Error to report if the right is bigger.
        -> Either (Error a n) (Maybe (Type n))

makeEffectWeakening k effLeft effRight onError
        -- When the effect of the left matches that of the right
        -- then we don't have to do anything else.
        | T.equivT EnvT.empty effLeft effRight
        = return Nothing

        -- When the effect of the right is smaller than that of
        -- the left then we need to wrap it in an effect weaking
        -- so the rewritten expression retains its original effect.
        | T.subsumesT EnvT.empty k effLeft effRight
        = return $ Just effLeft

        -- When the effect of the right is more than that of the left
        -- then this is an error. The rewritten expression can't have
        -- can't have more effects than the source.
        | otherwise
        = Left onError

{-
-- | Make the closure weakening for a rule.
--   This contains a closure term for all variables that are present
--   in the left of a rule but not in the right.
--
makeClosureWeakening
        :: (Ord n, Pretty n, Show n)
        => C.Config n           -- ^ Type-checker config
        -> EnvX n               -- ^ Type checker environment.
        -> Exp (C.AnTEC a n) n  -- ^ Expression on the left of the rule.
        -> Exp (C.AnTEC a n) n  -- ^ Expression on the right of the rule.
        -> Either (Error a n)
                  [Exp (C.AnTEC a n) n]

makeClosureWeakening config env lhs rhs
 = let  lhs'         = removeEffects config env lhs
        supportLeft  = support Env.empty Env.empty lhs'
        daLeft  = supportDaVar supportLeft
        wiLeft  = supportWiVar supportLeft
        spLeft  = supportSpVar supportLeft

        rhs'         = removeEffects config env rhs
        supportRight = support Env.empty Env.empty rhs'
        daRight = supportDaVar supportRight
        wiRight = supportWiVar supportRight
        spRight = supportSpVar supportRight

        a       = annotOfExp lhs

   in   Right
         $  [XVar a u
                | u <- Set.toList $ daLeft `Set.difference` daRight ]

         ++ [XWitness a (WVar a u)
                | u <- Set.toList $ wiLeft `Set.difference` wiRight ]

         ++ [XType a (TVar u)
                | u <- Set.toList $ spLeft `Set.difference` spRight ]

-- | Replace all effects with !0.
--   This is done so that when @makeClosureWeakening@ finds free variables,
--   it ignores those only mentioned in effects.
removeEffects
        :: (Ord n, Pretty n, Show n)
        => C.Config n   -- ^ Type-checker config
        -> EnvX n       -- ^ Type checker environment.
        -> Exp a n      -- ^ Target expression - has all effects replaced with bottom.
        -> Exp a n

removeEffects config
 = transformUpX remove
 where
  remove _env x

   | XApp a1 x1 (RType et)    <- x
   , Right (_, k)  <- C.checkSpec config et
   , T.isEffectKind k
   = XApp a1 x1 (RType $ T.tBot T.kEffect)

   | otherwise
   = x
-}


-- Structural Checks ----------------------------------------------------------
-- | Check for rule variables that have no uses.
checkUnmentionedBinders
        :: Ord n
        => [(BindMode, Bind n)]
        -> Exp (C.AnTEC a n) n
        -> Either (Error a n) ()

checkUnmentionedBinders bs expr
 = let  used  = C.freeX T.empty expr `Set.union` C.freeT T.empty expr

        binds = Set.fromList
              $ Maybe.catMaybes
              $ map (T.takeSubstBoundOfBind . snd) bs

   in   if binds `Set.isSubsetOf` used
         then return ()
         else Left ErrorVarUnmentioned


-- | Check for anonymous binders in the rule. We don't handle these.
checkAnonymousBinders
        :: [(BindMode, Bind n)]
        -> Either (Error a n) ()

checkAnonymousBinders bs
        | (b:_) <- filter T.isBAnon $ map snd bs
        = Left $ ErrorAnonymousBinder b

        | otherwise
        = return ()


-- | Check whether the form of the left-hand side of the rule is valid
--   we can only match against nested applications, and not general
--   expressions containing let-bindings and the like.
checkValidPattern :: Exp a n -> Either (Error a n) ()
checkValidPattern expr
 = go expr
 where  go (XVar _ _)           = return ()
        go x@(XAbs _ _ _)       = Left $ ErrorNotFirstOrder x
        go (XApp _ l r)         = go l >> go_a r
        go x@(XLet _ _ _)       = Left $ ErrorNotFirstOrder x
        go XAtom{}              = return ()
        go x@(XCase _ _ _)      = Left $ ErrorNotFirstOrder x
        go (XCast _ _ x)        = go x
        go x@(XAsync _ _ _ _)   = Left $ ErrorNotFirstOrder x

        go_t (TVar _)           = return ()
        go_t (TCon _)           = return ()
        go_t t@(TAbs _ _)       = Left $ ErrorNotFirstOrderType t
        go_t (TApp l r)         = go_t l >> go_t r
        go_t t@(TForall _ _)    = Left $ ErrorNotFirstOrderType t
        go_t (TSum _)           = return ()
        go_t (TRow _)           = return ()

        go_a (RType t)          = go_t t
        go_a (RWitness _)       = return ()
        go_a (RTerm x)          = go x
        go_a (RImplicit (RTerm x)) = go x
        go_a (RImplicit _)      = return ()


-- | Count how many times each binder is used in right-hand side.
countBinderUsage
        :: Ord n
        => [(BindMode, Bind n)]
        -> Exp a n
        -> Either (Error a n) [(BindMode, Bind n)]

countBinderUsage bs x
 = let  U.UsedMap um
                = fst $ annotOfExp $ U.usageX x

        get (BMValue _, BName n t)
         = (BMValue
                $ length
                $ Maybe.fromMaybe []
                $ Map.lookup n um
           , BName n t)

        get b
         = b

   in   return $ map get bs


-- | Allow the expressions and anything else with annotations to be reannotated
instance Reannotate RewriteRule where
 reannotate f (RewriteRule bs cs lhs hole rhs eff clo fv)
   = RewriteRule bs cs (re lhs) (fmap re hole) (re rhs) eff (map re clo) fv
    where
     re = reannotate f

