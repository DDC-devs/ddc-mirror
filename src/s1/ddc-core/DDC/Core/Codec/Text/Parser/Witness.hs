
module DDC.Core.Codec.Text.Parser.Witness
        ( pWitness
        , pWitnessApp
        , pWitnessAtom)
where
import DDC.Core.Codec.Text.Parser.Type
import DDC.Core.Codec.Text.Parser.Context
import DDC.Core.Codec.Text.Parser.Base
import DDC.Core.Codec.Text.Lexer.Tokens
import DDC.Core.Exp
import DDC.Data.Pretty
import DDC.Control.Parser               ((<?>), SourcePos)
import qualified DDC.Control.Parser     as P
import qualified DDC.Type.Exp.Simple    as T
import Control.Monad


-- | Parse a witness expression.
pWitness
        :: (Ord n, Pretty n)
        => Context n -> Parser n (Witness SourcePos n)
pWitness c = pWitnessJoin c


-- | Parse a witness join.
pWitnessJoin
        :: (Ord n, Pretty n)
        => Context n -> Parser n (Witness SourcePos n)
pWitnessJoin c
   -- WITNESS  or  WITNESS & WITNESS
 = do   w1      <- pWitnessApp c
        P.choice
         [ do   return w1 ]


-- | Parse a witness application.
pWitnessApp
        :: (Ord n, Pretty n)
        => Context n -> Parser n (Witness SourcePos n)

pWitnessApp c
  = do  (x:xs)  <- P.many1 (pWitnessArgSP c)
        let x'  = fst x
        let sp  = snd x
        let xs' = map fst xs
        return  $ foldl (WApp sp) x' xs'

 <?> "a witness expression or application"


-- | Parse a witness argument.
pWitnessArgSP
        :: (Ord n, Pretty n)
        => Context n -> Parser n (Witness SourcePos n, SourcePos)

pWitnessArgSP c
 = P.choice
 [ -- [TYPE]
   do   sp      <- pSym SSquareBra
        t       <- pType c
        pSym    SSquareKet
        return  (WType sp t, sp)

   -- WITNESS
 , do   pWitnessAtomSP c ]



-- | Parse a variable, constructor or parenthesised witness.
pWitnessAtom
        :: (Ord n, Pretty n)
        => Context n -> Parser n (Witness SourcePos n)

pWitnessAtom c
        = liftM fst (pWitnessAtomSP c)


-- | Parse a variable, constructor or parenthesised witness,
--   also returning source position.
pWitnessAtomSP
        :: (Ord n, Pretty n)
        => Context n -> Parser n (Witness SourcePos n, SourcePos)

pWitnessAtomSP c
 = P.choice
   -- (WITNESS)
 [ do   sp      <- pSym SRoundBra
        w       <- pWitness c
        pSym SRoundKet
        return  (w, sp)

   -- Named constructors
 , do   (con, sp) <- pConSP
        return  (WCon sp (WiConBound (UName con) (T.tBot T.kWitness)), sp)

   -- Debruijn indices
 , do   (i, sp) <- pIndexSP
        return  (WVar sp (UIx   i), sp)

   -- Variables
 , do   (var, sp) <- pVarSP
        return  (WVar sp (UName var), sp) ]

 <?> "a witness"
