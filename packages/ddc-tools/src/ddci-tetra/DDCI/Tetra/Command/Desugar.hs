
module DDCI.Tetra.Command.Desugar
        (cmdDesugar)
where
import DDC.Interface.Source
import DDCI.Tetra.State
import DDC.Base.Pretty
import DDC.Source.Tetra.Lexer
import DDC.Source.Tetra.Parser
import DDC.Source.Tetra.Pretty          ()
import DDC.Source.Tetra.Transform.Defix
import qualified DDC.Core.Lexer         as C
import qualified DDC.Base.Parser        as BP


cmdDesugar :: State -> Source -> String -> IO ()
cmdDesugar _state source str
 = goLex
 where  goLex 
         = let  tokens  = lexModuleString (nameOfSource source) 1 str
           in   goParse tokens

        goParse tokens
         = let  context = Context
                        { contextTrackedEffects         = True
                        , contextTrackedClosures        = True
                        , contextFunctionalEffects      = False
                        , contextFunctionalClosures     = False }

           in   case BP.runTokenParser C.describeTok (nameOfSource source)
                        (pModule False context) tokens of
                 Left err        -> error $ show err
                 Right mm        -> goDesugar mm

        goDesugar mm
         = case defix defaultFixTable mm of
            Left err    -> putStrLn (renderIndent $ ppr err)
            Right mm'   -> putStrLn (renderIndent $ ppr mm')
