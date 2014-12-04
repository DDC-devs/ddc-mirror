
module DDC.Core.Lite.Name
        ( Name          (..) 

        -- * Baked in global effect type constructors.
        , EffectTyCon   (..)

        -- * Baked in Algebraic Data Types
        , DataTyCon     (..)
        , PrimDaCon     (..)

        -- * Primitive Type Constructors
        , PrimTyCon     (..)

        -- * Primitive Operators
        , PrimArith     (..)
        , PrimCast      (..)

        -- * Name Parsing
        , readName)
where
import DDC.Core.Salt.Name.PrimTyCon
import DDC.Core.Salt.Name.PrimArith
import DDC.Core.Salt.Name.PrimCast
import DDC.Core.Salt.Name.Lit
import DDC.Base.Pretty
import DDC.Base.Name
import DDC.Data.ListUtils
import Control.DeepSeq
import Data.Typeable
import Data.Char


-- | Names of things used in Disciple Core Lite.
data Name
        -- | User defined variables.
        = NameVar               String

        -- | A user defined constructor.
        | NameCon               String

        -- | An extended name.
        | NameExt               Name String

        -- | Baked in effect type constructors.
        | NameEffectTyCon       EffectTyCon

        -- | Baked in data type constructors.
        | NameDataTyCon         DataTyCon

        -- | A primitive data constructor.
        | NamePrimDaCon         PrimDaCon

        -- | A primitive type constructor.
        | NamePrimTyCon         PrimTyCon

        -- | Primitive arithmetic, logic, comparison and bit-wise operators.
        | NamePrimArith         PrimArith

        -- | Primitive casting between numeric types.
        | NamePrimCast          PrimCast

        -- | An unboxed boolean literal
        | NameLitBool           Bool

        -- | An unboxed natural literal.
        | NameLitNat            Integer

        -- | An unboxed integer literal.
        | NameLitInt            Integer

        -- | An unboxed word literal
        | NameLitWord           Integer Int
        deriving (Eq, Ord, Show, Typeable)


instance NFData Name where
 rnf nn
  = case nn of
        NameVar s               -> rnf s
        NameCon s               -> rnf s
        NameExt n s             -> rnf n `seq` rnf s
        NameEffectTyCon con     -> rnf con
        NameDataTyCon con       -> rnf con
        NamePrimDaCon con       -> rnf con
        NamePrimTyCon con       -> rnf con
        NamePrimArith con       -> rnf con
        NamePrimCast  c         -> rnf c
        NameLitBool b           -> rnf b
        NameLitNat  n           -> rnf n
        NameLitInt  i           -> rnf i
        NameLitWord i bits      -> rnf i `seq` rnf bits


instance Pretty Name where
 ppr nn
  = case nn of
        NameVar v               -> text v
        NameCon c               -> text c
        NameExt n s             -> ppr n <> text "$" <> text s
        NameEffectTyCon con     -> ppr con
        NameDataTyCon dc        -> ppr dc
        NamePrimTyCon tc        -> ppr tc
        NamePrimDaCon dc        -> ppr dc
        NamePrimArith op        -> ppr op
        NamePrimCast  op        -> ppr op
        NameLitBool True        -> text "True#"
        NameLitBool False       -> text "False#"
        NameLitNat  i           -> integer i <> text "#"
        NameLitInt  i           -> integer i <> text "i" <> text "#"
        NameLitWord i bits      -> integer i <> text "w" <> int bits <> text "#"


instance CompoundName Name where
 extendName n str       
  = NameExt n str
 
 splitName nn
  = case nn of
        NameExt n str   -> Just (n, str)
        _               -> Nothing


-- | Read the name of a variable, constructor or literal.
readName :: String -> Maybe Name
readName str
        |  Just name    <- readEffectTyCon str
        =  Just $ NameEffectTyCon name

        |  Just name    <- readDataTyCon str
        =  Just $ NameDataTyCon name

        |  Just name    <- readPrimTyCon str
        =  Just $ NamePrimTyCon name

        |  Just name    <- readPrimDaCon str
        =  Just $ NamePrimDaCon name

        -- PrimArith
        | Just p        <- readPrimArith str
        = Just $ NamePrimArith p

        -- PrimCast
        | Just p        <- readPrimCast  str
        = Just $ NamePrimCast p

        -- Literal unit value.
        | str == "()"
        = Just $ NamePrimDaCon PrimDaConUnit

        -- Literal Bools
        | str == "True#"  = Just $ NameLitBool True
        | str == "False#" = Just $ NameLitBool False

        -- Literal Nat
        | Just str'     <- stripSuffix "#" str
        , Just val      <- readLitNat  str'
        = Just $ NameLitNat  val

        -- Literal Ints
        | Just str'     <- stripSuffix "#" str
        , Just val      <- readLitInt  str'
        = Just $ NameLitInt  val

        -- Literal Words
        | Just str'     <- stripSuffix "#" str
        , Just (val, bits) <- readLitWordOfBits str'
        , elem bits [8, 16, 32, 64]
        = Just $ NameLitWord val bits

        -- Constructors.
        | c : _         <- str
        , isUpper c
        = Just $ NameCon str

        -- Variables.
        | c : _         <- str
        , isLower c      
        = Just $ NameVar str

        | otherwise
        = Nothing


-- EffectTyCon ----------------------------------------------------------------
-- | Baked-in effect type constructors.
data EffectTyCon
        = EffectTyConConsole    -- ^ @Console@ type constructor.
        deriving (Eq, Ord, Show)

instance NFData EffectTyCon

instance Pretty EffectTyCon where
 ppr tc
  = case tc of
        EffectTyConConsole      -> text "Console"


-- | Read a baked-in effect type constructor.
readEffectTyCon :: String -> Maybe EffectTyCon
readEffectTyCon str
 = case str of
        "Console"       -> Just EffectTyConConsole
        _               -> Nothing


-- DataTyCon ------------------------------------------------------------------
-- | Baked-in data type constructors.
data DataTyCon
        = DataTyConUnit         -- ^ @Unit@  type constructor.
        | DataTyConBool         -- ^ @Bool@  type constructor.
        | DataTyConNat          -- ^ @Nat@   type constructor.
        | DataTyConInt          -- ^ @Int@   type constructor.
        | DataTyConPair         -- ^ @Pair@  type constructor.
        | DataTyConList         -- ^ @List@  type constructor.
        deriving (Eq, Ord, Show)

instance NFData DataTyCon

instance Pretty DataTyCon where
 ppr dc
  = case dc of
        DataTyConUnit           -> text "Unit"
        DataTyConBool           -> text "Bool"
        DataTyConNat            -> text "Nat"
        DataTyConInt            -> text "Int"
        DataTyConPair           -> text "Pair"
        DataTyConList           -> text "List"


-- | Read a baked-in data type constructor.
readDataTyCon :: String -> Maybe DataTyCon
readDataTyCon str
 = case str of
        "Unit"          -> Just DataTyConUnit
        "Bool"          -> Just DataTyConBool
        "Nat"           -> Just DataTyConNat
        "Int"           -> Just DataTyConInt
        "Pair"          -> Just DataTyConPair
        "List"          -> Just DataTyConList
        _               -> Nothing


-- PrimDaCon ------------------------------------------------------------------
-- | Baked-in data constructors.
data PrimDaCon
        = PrimDaConUnit         -- ^ Unit   data constructor @()@.
        | PrimDaConBoolU        -- ^ @B#@   data constructor.
        | PrimDaConNatU         -- ^ @N#@   data constructor.
        | PrimDaConIntU         -- ^ @I#@   data constructor.
        | PrimDaConPr           -- ^ @Pr@   data construct (pairs).
        | PrimDaConNil          -- ^ @Nil@  data constructor (lists).
        | PrimDaConCons         -- ^ @Cons@ data constructor (lists).
        deriving (Show, Eq, Ord)

instance NFData PrimDaCon

instance Pretty PrimDaCon where
 ppr dc
  = case dc of
        PrimDaConBoolU          -> text "B#"
        PrimDaConNatU           -> text "N#"
        PrimDaConIntU           -> text "I#"

        PrimDaConUnit           -> text "()"
        PrimDaConPr             -> text "Pr"
        PrimDaConNil            -> text "Nil"
        PrimDaConCons           -> text "Cons"


-- | Read a Baked-in data constructor.
readPrimDaCon :: String -> Maybe PrimDaCon
readPrimDaCon str
 = case str of
        "B#"    -> Just PrimDaConBoolU
        "N#"    -> Just PrimDaConNatU
        "I#"    -> Just PrimDaConIntU

        "()"    -> Just PrimDaConUnit
        "Pr"    -> Just PrimDaConPr
        "Nil"   -> Just PrimDaConNil
        "Cons"  -> Just PrimDaConCons
        _       -> Nothing

