{-# LANGUAGE TypeFamilies, ConstraintKinds, UndecidableInstances, PatternSynonyms #-}

-- | Generic expression representation.
--
--   Each of these types is polymorphic in the names used for
--   (b)inding occurrences, bo(u)nd occurrences, (c)onstructors and (p)rimitives.
--
--   Clients of this module are expected to defined their own type synonyms
--   for 'Exp', 'Lets' and so on that instantiate each of these data types to
--   use more specific types for names.
--
module DDC.Core.Generic.Exp where
import DDC.Core.Exp.DaCon
import qualified DDC.Type.Exp   as T

---------------------------------------------------------------------------------------------------
class Language l where
 type Annot l
 type Bind  l    
 type Bound l
 type Prim  l


---------------------------------------------------------------------------------------------------
-- | Generic expression representation.
-- TODO: split XType and XWitness into GArg type.
data GExp l
        = XAnnot   !(Annot l)  !(GExp l)

        -- | Value or Witness variable (level-0).
        | XVar     !(Bound l)

        -- | Data constructor.
        | XCon     !(DaCon l)

        -- | Primitive operator or literal.
        | XPrim    !(Prim  l)

        -- | Function abstraction.
        | XAbs     !(GAbs  l)  !(GExp l)

        -- | Function application.
        | XApp     !(GExp  l)  !(GExp l)

        -- | Possibly recursive bindings.
        | XLet     !(GLets l)  !(GExp l)

        -- | Case branching.
        | XCase    !(GExp  l)  ![GAlt l]

        -- | Type casting.
        | XCast    !(GCast l)  !(GExp l)

        -- | Type can appear as the argument of an application.
        | XType    !(T.Type  l)

        -- | Witness can appear as the argument of an application.
        | XWitness !(GWitness l)


-- | Abstractions.
--
--   This indicates what sort of object is being abstracted over in an XAbs.
--
data GAbs l
        -- | Level-1 abstraction (spec)
        = ALAM     !(Bind l)

        -- | Level-0 abstraction (value and witness)
        | ALam     !(Bind l)

pattern XLAM b x = XAbs (ALAM b) x
pattern XLam b x = XAbs (ALam b) x


-- | Possibly recursive bindings.
data GLets l
        -- | Non-recursive binding.
        = LLet     !(Bind l)  !(GExp l)

        -- | Recursive binding.
        | LRec     ![(Bind l, GExp l)]

        -- | Introduce a private region variable and witnesses to its properties.
        | LPrivate ![Bind l] !(Maybe (T.Type l)) ![Bind l]


-- | Case alternatives.
data GAlt l
        = AAlt !(GPat l) !(GExp l)


-- | Patterns.
data GPat l
        -- | The default pattern always succeeds.
        = PDefault

        -- | Match a data constructor and bind its arguments.
        | PData !(DaCon l) ![Bind l]


-- | Type casts.
data GCast l
        -- | Weaken the effect of an expression.
        = CastWeakenEffect   !(T.Type l)

        -- | Purify the effect of an expression.
        | CastPurify         !(GWitness l)

        -- | Box up a computation, suspending its evaluation and capturing 
        --   its effects in the S computaiton type.
        | CastBox

        -- | Run a computation, releasing its effects into the context.
        | CastRun


-- | Witnesses.
data GWitness l
        -- | Witness variable.
        = WVar  !(Bound l)

        -- | Witness constructor.
        | WCon  !(GWiCon l)

        -- | Witness application.
        | WApp  !(GWitness l) !(GWitness l)

        -- | Type can appear as an argument of a witness application.
        | WType !(T.Type l)


-- | Witness constructors.
data GWiCon l
        -- | Witness constructors defined in the environment.
        --   In the interpreter we use this to hold runtime capabilities.
        --   The attached type must be closed.
        = WiConBound   !(Bound l) !(T.Type l)


---------------------------------------------------------------------------------------------------
-- | Synonym for Show constraints of all language types.
type ShowLanguage l
        = (Show l, Show (Annot l), Show (Bind l), Show (Bound l), Show (Prim l))

deriving instance ShowLanguage l => Show (GExp     l)
deriving instance ShowLanguage l => Show (GAbs     l)
deriving instance ShowLanguage l => Show (GLets    l)
deriving instance ShowLanguage l => Show (GAlt     l)
deriving instance ShowLanguage l => Show (GPat     l)
deriving instance ShowLanguage l => Show (GCast    l)
deriving instance ShowLanguage l => Show (GWitness l)
deriving instance ShowLanguage l => Show (GWiCon   l)

