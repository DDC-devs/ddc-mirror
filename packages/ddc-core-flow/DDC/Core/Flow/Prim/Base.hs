
module DDC.Core.Flow.Prim.Base
        ( Name (..)
        , KiConFlow     (..)
        , TyConFlow     (..)
        , DaConFlow     (..)
        , OpFlow        (..)
        , OpControl     (..)
        , OpStore       (..)
        , PrimTyCon     (..)
        , PrimArith     (..)
        , PrimVec       (..)
        , PrimCast      (..))
where
import Data.Typeable
import DDC.Core.Salt.Name.PrimTyCon
import DDC.Core.Salt.Name.PrimArith
import DDC.Core.Salt.Name.PrimVec
import DDC.Core.Salt.Name.PrimCast


-- | Names of things used in Disciple Core Flow.
data Name
        -- | User defined variables.
        = NameVar               String

        -- | A name generated by modifying some other name `name$mod`
        | NameVarMod            Name String

        -- | A user defined constructor.
        | NameCon               String

        -- Fragment specific primops -----------
        -- | Fragment specific kind constructors.
        | NameKiConFlow         KiConFlow

        -- | Fragment specific type constructors.
        | NameTyConFlow         TyConFlow

        -- | Fragment specific data constructors.
        | NameDaConFlow         DaConFlow

        -- | Flow operators.
        | NameOpFlow            OpFlow

        -- | Control operators.
        | NameOpControl         OpControl

        -- | Store operators.
        | NameOpStore           OpStore


        -- Machine primitives ------------------
        -- | A primitive type constructor.
        | NamePrimTyCon         PrimTyCon

        -- | Primitive arithmetic, logic, comparison and bit-wise operators.
        | NamePrimArith         PrimArith

        -- | Primitive casting between numeric types.
        | NamePrimCast          PrimCast

        -- | Primitive vector operators.
        | NamePrimVec           PrimVec


        -- Literals -----------------------------
        -- | A boolean literal.
        | NameLitBool           Bool

        -- | A natural literal.
        | NameLitNat            Integer

        -- | An integer literal.
        | NameLitInt            Integer

        -- | A word literal, with the given number of bits precision.
        | NameLitWord           Integer  Int

        -- | A float literal, with the given number of bits precision.
        | NameLitFloat          Rational Int
        deriving (Eq, Ord, Show, Typeable)


-- | Fragment specific kind constructors.
data KiConFlow
        = KiConFlowRate
        deriving (Eq, Ord, Show)


-- | Fragment specific type constructors.
data TyConFlow
        -- | @TupleN#@ constructor. Tuples.
        = TyConFlowTuple Int            

        -- | @Vector#@ constructor. Vectors. 
        | TyConFlowVector

        -- | @Series#@ constructor. Series types.
        | TyConFlowSeries

        -- | @Segd#@   constructor. Segment Descriptors.
        | TyConFlowSegd

        -- | @SelN#@   constructor. Selectors.
        | TyConFlowSel Int

        -- | @Ref#@    constructor.  References.
        | TyConFlowRef                  

        -- | @World#@  constructor.  State token used when converting to GHC core.
        | TyConFlowWorld

        -- | @RateNat#@ constructor. Naturals witnessing a type-level Rate.          
        | TyConFlowRateNat

        -- | @DownN#@ constructor.   Rate decimation. 
        | TyConFlowDown  Int
        deriving (Eq, Ord, Show)


-- | Primitive data constructors.
data DaConFlow
        -- | @TN@ data constructor.
        = DaConFlowTuple Int            
        deriving (Eq, Ord, Show)


-- | Flow operators.
data OpFlow
        -- | Project out a component of a tuple,
        --   given the tuple arity and index of the desired component.
        = OpFlowProj Int Int

        -- | Take the rate of a series.
        | OpFlowRateOfSeries

        -- | Take the underlying @Nat@ of a @RateNat@.
        | OpFlowNatOfRateNat

        -- | Apply a worker to corresponding elements of some series.
        | OpFlowMap Int

        -- | Replicate a single element into a series.
        | OpFlowRep

        -- | Segmented replicate.
        | OpFlowReps

        -- | Make a selector.
        | OpFlowMkSel Int

        -- | Pack a series according to a flags vector.
        | OpFlowPack

        -- | Reduce a series with an associative operator,
        --   updating an existing accumulator.
        | OpFlowReduce

        -- | Fold a series with an associative operator,
        --   returning the final result.
        | OpFlowFold

        -- | Fold where the worker also takes the current index into the series.
        | OpFlowFoldIndex

        -- | Segmented fold.
        | OpFlowFolds

        -- | Create a new vector from a series.
        | OpFlowCreate

        -- | Fill an existing vector from a series.
        | OpFlowFill

        -- | Gather  (read) elements from a vector.
        | OpFlowGather

        -- | Scatter (write) elements into a vector.
        | OpFlowScatter
        deriving (Eq, Ord, Show)


-- | Control operators.
data OpControl
        = OpControlLoop
        | OpControlLoopN
        | OpControlGuard
        deriving (Eq, Ord, Show)


-- | Store operators.
data OpStore
        -- Assignables ----------------
        -- | Allocate a new reference.
        = OpStoreNew            

        -- | Read from a reference.
        | OpStoreRead

        -- | Write to a reference.
        | OpStoreWrite


        -- Vectors --------------------
        -- | Allocate a new vector (taking a @Nat@ for the length)
        | OpStoreNewVector

        -- | Allocate a new vector (taking a @Rate@ for the length)
        | OpStoreNewVectorR     

        -- | Allocate a new vector (taking a @RateNat@ for the length)
        | OpStoreNewVectorN     

        -- | Read a packed Vec of values from a Vector buffer.
        | OpStoreReadVector     Int

        -- | Write a packed Vec of values to a Vector buffer.
        | OpStoreWriteVector    Int

        -- | Slice after a pack/filter (taking a @Nat@ for new length)
        | OpStoreSliceVector    


        -- Series --------------------
        -- | Take some elements from a series.
        | OpStoreNext Int
        deriving (Eq, Ord, Show)

