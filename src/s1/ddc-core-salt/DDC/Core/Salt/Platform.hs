
module DDC.Core.Salt.Platform
        ( Platform      (..)
        , platform32
        , platform64)
where
import DDC.Data.Pretty


-- | Enough information about the platform to generate code for it.
--   We need to know the pointer size and alignment constraints
--   so that we can lay out heap objects.
data Platform
        = Platform
        { -- | Width of an address in bytes.
          platformAddrBytes     :: Integer

          -- | Width of a constructor tag in bytes.
        , platformTagBytes      :: Integer

          -- | Width of a Nat in bytes (used for object sizes like size_t).
        , platformNatBytes      :: Integer

          -- | Align functions on this boundary in bytes.
        , platformAlignBytes    :: Integer

          -- | Minimum size of a heap object in bytes.
        , platformObjBytes      :: Integer }
        deriving Show

instance Pretty Platform where
 ppr pp
  = vcat
        [ text "Address Width       (bytes) : "
                <> text (show $ platformAddrBytes  pp)

        , text "Tag Word Width      (bytes) : "
                <> text (show $ platformTagBytes   pp)

        , text "Nat Word Width      (bytes) : "
                <> text (show $ platformNatBytes   pp)

        , text "Function Alignment  (bytes) : "
                <> text (show $ platformAlignBytes pp)

        , text "Minimum Object Size (bytes) : "
                <> text (show $ platformObjBytes   pp) ]


-- | 32-bit platform specification.
--
--   Heap objects are aligned to 64-bit so that double-precision floats
--   in the object payloads maintain their alignments.
platform32 :: Platform
platform32
        = Platform
        { platformAddrBytes     = 4
        , platformTagBytes      = 4
        , platformNatBytes      = 4
        , platformAlignBytes    = 4
        , platformObjBytes      = 8 }


-- | 64-bit platform specification.
platform64 :: Platform
platform64
        = Platform
        { platformAddrBytes     = 8
        , platformTagBytes      = 8
        , platformNatBytes      = 8
        , platformAlignBytes    = 8
        , platformObjBytes      = 8 }

