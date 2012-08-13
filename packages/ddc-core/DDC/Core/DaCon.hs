

-- | Data constructors.
module DDC.Core.DaCon 
        ( DaCon         (..)
        , DaConName     (..)
        , takeNameOfDaCon
        , typeOfDaCon
        , dcUnit
        , mkDaConAlg)
where
import DDC.Type.Compounds
import DDC.Type.Exp


-- | Data constructors.
data DaCon n
        = DaCon
        { -- | Name of the data constructor.
          daConName             :: DaConName n

          -- | Type of the data constructor.
        , daConType             :: Type n

          -- | Algebraic constructors can be deconstructed with case-expressions,
          --   and must have a data type declaration for their types.
        , daConIsAlgebraic      :: Bool }
        deriving Show


-- | Data constructor names.
data DaConName n
        -- | The unit data constructor is builtin.
        = DaConUnit

        -- | Data constructor name defined by the client.
        | DaConNamed n
        deriving (Eq, Show)


-- | Take the name of data constructor.
takeNameOfDaCon :: DaCon n -> Maybe n
takeNameOfDaCon dc
 = case daConName dc of
        DaConUnit               -> Nothing
        DaConNamed n            -> Just n


-- | Take the type annotation of a data constructor.
typeOfDaCon :: DaCon n -> Type n
typeOfDaCon dc  = daConType dc


-- | The unit data constructor.
dcUnit  :: DaCon n
dcUnit  = DaCon
        { daConName             = DaConUnit
        , daConType             = tUnit
        , daConIsAlgebraic      = False }


-- | Make an algebraic data constructor.
mkDaConAlg :: n -> Type n -> DaCon n
mkDaConAlg n t
        = DaCon
        { daConName             = DaConNamed n
        , daConType             = t
        , daConIsAlgebraic      = True }

