
-- | Names used in the SeaOutput language profile.
--   These map directly onto names used in the C output language.
module DDC.Core.Sea.Output.Name
        ( Name            (..)
        , Prim            (..)
        , PrimTyCon       (..)
        , PrimOp          (..)
        , PrimCast        (..)
        , PrimCall        (..)
        , PrimControl     (..)
        , PrimStore       (..)
        , PrimExternal    (..)
        , readName)
where
import DDC.Core.Sea.Base.Name
import DDC.Base.Pretty
import Data.Char
import Data.List


-- Names of things recognised by the Sea backend.
data Name
        -- | A type or value variable
        = NameVar       String

        -- | The object type constructor.
        | NameObjTyCon

        -- | A type primitive constructor.
        | NamePrimTyCon PrimTyCon

        -- | A primitive operator.
        | NamePrim      Prim

        -- | A natural number literal.
        | NameNat       Integer

        -- | A constructor tag literal.
        | NameTag       Integer

        -- | A boolean literal.
        | NameBool      Bool

        -- | A WordN literal, of the given width.
        | NameWord      Integer Int

        -- | An IntN literal, of the given width.
        | NameInt       Integer Int
        deriving (Eq, Ord, Show)


instance Pretty Name where
 ppr nn
  = case nn of
        NameVar  n        -> text n
        NameObjTyCon      -> text "Obj"
        NamePrimTyCon tc  -> ppr tc
        NamePrim p        -> ppr p
        NameNat  i        -> integer i
        NameTag  i        -> text "TAG" <> integer i
        NameBool True     -> text "True#"
        NameBool False    -> text "False#"
        NameWord i bits   -> integer i <> text "w" <> int bits
        NameInt  i bits   -> integer i <> text "i" <> int bits


readName :: String -> Maybe Name
readName str
        -- Obj 
        | str == "Obj"
        = Just $ NameObjTyCon

        -- PrimTyCon
        | Just p        <- readPrimTyCon str
        = Just $ NamePrimTyCon p

        -- PrimOp
        | Just p        <- readPrimOp str
        = Just $ NamePrim $ PrimOp p

        -- PrimCast
        | Just p        <- readPrimCast str
        = Just $ NamePrim $ PrimCast p

        -- PrimCall
        | Just p        <- readPrimCall str
        = Just $ NamePrim $ PrimCall p

        -- PrimControl
        | Just p        <- readPrimControl str
        = Just $ NamePrim $ PrimControl p

        -- PrimStore
        | Just p        <- readPrimStore str
        = Just $ NamePrim $ PrimStore p

        -- PrimExternal
        | Just p        <- readPrimExternal str
        = Just $ NamePrim $ PrimExternal p

        -- Literal Nats.
        | (ds, "")        <- span isDigit str
        = Just $ NameNat (read ds)        

        -- Literal Tags
        | Just rest       <- stripPrefix "TAG" str
        , (ds, "#")       <- span isDigit rest
        = Just $ NameTag (read ds)

        -- Literal Bools
        | str == "True#"  = Just $ NameBool True
        | str == "False#" = Just $ NameBool False

        -- Literal Words
        | Just (val, bits) <- readWordOfBits str
        = Just $ NameWord val bits

        -- Literal Ints
        | Just (val, bits) <- readIntOfBits str
        = Just $ NameInt  val bits

        -- Variables.
        -- This needs to come last because the primops can also be parsed
        -- as variables.
        | c : _         <- str
        , isLower c      
        = Just $ NameVar str

        | otherwise
        = Nothing


-- Read a word like 1234w32
readWordOfBits :: String -> Maybe (Integer, Int)
readWordOfBits str1
        | (ds, str2)    <- span isDigit str1
        , Just str3     <- stripPrefix "w" str2
        , (bs, "#")     <- span isDigit str3
        = Just $ (read ds, read bs)

        | otherwise
        = Nothing


-- Read an integer like 1234i32.
-- TODO hande negative literals.
readIntOfBits :: String -> Maybe (Integer, Int)
readIntOfBits str1
        | (ds, str2)    <- span isDigit str1
        , Just str3     <- stripPrefix "i" str2
        , (bs, "#")     <- span isDigit str3
        = Just $ (read ds, read bs)

        | otherwise
        = Nothing

-- Prim -----------------------------------------------------------------------
-- | Primitive operators implemented directly by the machine or runtime system.
data    Prim
        -- | Arithmetic and bitwise-operators.
        = PrimOp        PrimOp

        -- | Casting between numeric types.
        | PrimCast      PrimCast

        -- | Funtion calls.
        | PrimCall      PrimCall

        -- | Control flow.
        | PrimControl   PrimControl

        -- | Store access.
        | PrimStore     PrimStore

        -- | External things that should really be imported with an FFI.
        --   We'll remove these when we get the FFI working.
        | PrimExternal  PrimExternal
        deriving (Eq, Ord, Show)


instance Pretty Prim where
 ppr pp
  = case pp of
        PrimOp       op -> ppr op
        PrimCast     c  -> ppr c
        PrimCall     c  -> ppr c
        PrimControl  c  -> ppr c
        PrimStore    p  -> ppr p
        PrimExternal p  -> ppr p


-- PrimCast -------------------------------------------------------------------
-- | Primitive cast between two types.
data PrimCast
        = PrimCastOp
        | PrimCastNatToInt Int
        deriving (Eq, Ord, Show)


instance Pretty PrimCast where
 ppr c
  = case c of
        PrimCastOp      -> text "cast#"

        PrimCastNatToInt bits
         -> text "i" <> int bits <> text "#"


readPrimCast :: String -> Maybe PrimCast
readPrimCast str
        -- General cast.
        | str == "cast#"
        = Just $ PrimCastOp

        -- Cast Nat to Int
        | Just rest     <- stripPrefix "i" str
        , (ds, "#")     <- span isDigit rest
        , bits          <- read ds
        , elem bits [8, 16, 32, 64]
        = Just $ PrimCastNatToInt bits

        | otherwise
        = Nothing


-- PrimCall -------------------------------------------------------------------
-- | Primitive ways of invoking a function, 
--   where control flow returns back to the caller.
data PrimCall
        -- | Tailcall a function
        = PrimCallTail    Int
        deriving (Eq, Ord, Show)


instance Pretty PrimCall where
 ppr pc
  = case pc of
        PrimCallTail    arity
         -> text "tailcall" <> int arity <> text "#"


readPrimCall :: String -> Maybe PrimCall
readPrimCall str

        -- tailcallN#
        | Just rest     <- stripPrefix "tailcall" str
        , (ds, "#")     <- span isDigit rest
        , not $ null ds
        , n             <- read ds
        , n > 0
        = Just $ PrimCallTail n

        | otherwise
        = Nothing


-- PrimControl ----------------------------------------------------------------
-- | Primitive non-returning control flow.
data PrimControl
        -- | Ungraceful failure -- just abort the program.
        --   This is called on internal errors in the runtime system.
        --   There is no further debugging info provided, so you'll need to 
        --   look at the stack trace to debug it.
        = PrimControlFail

        -- | Return from the enclosing function with the given value.
        | PrimControlReturn
        deriving (Eq, Ord, Show)


instance Pretty PrimControl where
 ppr pc
  = case pc of
        PrimControlFail         -> text "fail#"
        PrimControlReturn       -> text "return#"


readPrimControl :: String -> Maybe PrimControl
readPrimControl str
 = case str of
        "fail#"         -> Just $ PrimControlFail
        "return#"       -> Just $ PrimControlReturn
        _               -> Nothing


-- Store -----------------------------------------------------------------------
-- | A projection of some other object.
data PrimStore
        -- | Read a value from the store.
        = PrimStoreRead

        -- | Write a value to the store.
        | PrimStoreWrite

        -- | Allocate some space on the heap.
        | PrimStoreAlloc
        deriving (Eq, Ord, Show)


instance Pretty PrimStore where
 ppr p
  = case p of        
        PrimStoreRead           -> text "read#"
        PrimStoreWrite          -> text "write#"
        PrimStoreAlloc          -> text "alloc#"


readPrimStore :: String -> Maybe PrimStore
readPrimStore str
 = case str of
        "read#"         -> Just $ PrimStoreRead
        "write#"        -> Just $ PrimStoreWrite
        "alloc#"        -> Just $ PrimStoreAlloc
        _               -> Nothing


-- PrimExternal ---------------------------------------------------------------
-- | String funtions.
--   We're treating these as primops until we get the FFI working.
data PrimExternal
        = PrimExternalShowInt Int
        | PrimExternalPutStr
        | PrimExternalPutStrLn
        deriving (Eq, Ord, Show)


instance Pretty PrimExternal where
 ppr ps
  = case ps of
        PrimExternalShowInt i   -> text "showInt" <> int i <> text "#"
        PrimExternalPutStr      -> text "putStr#"
        PrimExternalPutStrLn    -> text "putStrLn#"


readPrimExternal :: String -> Maybe PrimExternal
readPrimExternal str
        -- showIntN#
        | Just rest     <- stripPrefix "showInt" str
        , (ds, "#")     <- span isDigit rest
        , bits          <- read ds
        , elem bits [8, 16, 32, 64]
        = Just $ PrimExternalShowInt bits

        | str == "putStr#"      
        = Just $ PrimExternalPutStr

        | str == "putStrLn#"    
        = Just $ PrimExternalPutStrLn

        | otherwise
        = Nothing

