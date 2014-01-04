module DDC.Driver.Command.Check
        ( cmdShowKind
        , cmdTypeEquiv
        , cmdShowWType
        , cmdShowType
        , cmdExpRecon
        , ShowTypeMode(..)
        , cmdCheckModuleFromFile
        , cmdCheckModuleFromString
        , cmdParseCheckType
        , cmdParseCheckExp,     Mode(..))
where
import DDC.Driver.Output
import DDC.Interface.Source
import DDC.Build.Language
import DDC.Core.Fragment
import DDC.Core.Load
import DDC.Core.Parser
import DDC.Core.Lexer
import DDC.Core.Module
import DDC.Core.Exp
import DDC.Core.Pretty
import DDC.Core.Compounds
import DDC.Type.Transform.SpreadT
import DDC.Type.Universe
import DDC.Type.Equiv
import Control.Monad.Trans.Error
import Control.Monad.IO.Class
import qualified DDC.Base.Parser        as BP
import qualified DDC.Type.Check         as T
import qualified DDC.Core.Check         as C
import Control.Monad


-- kind ------------------------------------------------------------------------
-- | Show the kind of a spec.
cmdShowKind :: Language -> Source -> String -> IO ()
cmdShowKind language source str
 | Language bundle      <- language
 , fragment             <- bundleFragment  bundle
 , profile              <- fragmentProfile fragment
 = let  srcName = nameOfSource source
        srcLine = lineStartOfSource source
        toks    = fragmentLexExp fragment srcName srcLine str
        eTK     = loadType profile UniverseSpec srcName toks
   in   case eTK of
         Left err       -> outDocLn $ ppr err
         Right (t, k)   -> outDocLn $ ppr t <+> text "::" <+> ppr k


-- tequiv ---------------------------------------------------------------------
-- | Check if two types are equivlant.
cmdTypeEquiv :: Language -> Source -> String -> IO ()
cmdTypeEquiv language source ss
 | Language bundle      <- language
 , fragment             <- bundleFragment  bundle
 , profile              <- fragmentProfile fragment
 = let  srcName = nameOfSource source
        srcLine = lineStartOfSource source
        
        goParse toks
         = case BP.runTokenParser describeTok (nameOfSource source)
                        (do t1 <- pTypeAtom (contextOfProfile profile)
                            t2 <- pTypeAtom (contextOfProfile profile)
                            return (t1, t2))
                        toks
            of Left err -> outDocLn $ text "parse error " <> ppr err
               Right tt -> goEquiv tt
         
        goEquiv (t1, t2)
         = do   b1 <- checkT t1
                b2 <- checkT t2
                if b1 && b2 
                 then outStrLn $ show $ equivT t1 t2    
                 else return ()


        config  = T.configOfProfile profile
        kenv    = profilePrimKinds    profile

        checkT t
         = case T.checkSpec config kenv (spreadT kenv t) of
                Left err 
                 -> do  outDocLn $ ppr err
                        return False

                Right{} 
                 ->     return True

   in goParse (fragmentLexExp fragment srcName srcLine ss)


-- wtype ----------------------------------------------------------------------
-- | Show the type of a witness.
cmdShowWType :: Language -> Source -> String -> IO ()
cmdShowWType language source str
 | Language bundle      <- language
 , fragment             <- bundleFragment  bundle
 , profile              <- fragmentProfile fragment
 = let  srcName = nameOfSource source
        srcLine = lineStartOfSource source
        toks    = fragmentLexExp fragment srcName srcLine str
        eTK     = loadWitness profile srcName toks
   in   case eTK of
         Left err       -> outDocLn $ ppr err
         Right (t, k)   -> outDocLn $ ppr t <+> text "::" <+> ppr k


-- check / type / effect / closure --------------------------------------------
-- | What components of the checked type to display.
data ShowTypeMode
        = ShowTypeAll
        | ShowTypeValue
        | ShowTypeEffect
        | ShowTypeClosure
        deriving (Eq, Show)


-- | Show the type of an expression.
cmdShowType 
        :: Language     -- ^ Language fragment.
        -> ShowTypeMode -- ^ What part of the type to show.
        -> Bool         -- ^ Type checker mode, Synth(True) or Recon(False)
        -> Bool         -- ^ Whether to display type checker trace.
        -> Source       -- ^ Source of the program text.
        -> String       -- ^ Program text.
        -> IO ()

cmdShowType language showMode checkMode shouldPrintTrace source ss
 | Language bundle      <- language
 , fragment             <- bundleFragment  bundle
 , modules              <- bundleModules   bundle
 =   cmdParseCheckExp fragment modules mode shouldPrintTrace True source ss 
 >>= goResult fragment
 where
        -- Determine the checker mode based on the flag we're given.
        -- We don't pass the mode directly because the Mode type is
        -- also parameterised over the type of names.
        mode    = case checkMode of
                        True    -> Synth
                        False   -> Recon

        goResult fragment (Just x, Just ct)
         = let  annot    = annotOfExp x
                t        = annotType annot
                eff      = annotEffect annot
                clo      = annotClosure annot
                features = profileFeatures $ fragmentProfile fragment

           in case showMode of
                ShowTypeAll
                 -> do  outDocLn $ ppr x
                        outDocLn $ text ":*:" <+> ppr t
                        
                        when (featuresTrackedEffects  features)
                         $ outDocLn $ text ":!:" <+> ppr eff

                        when (featuresTrackedClosures features)
                         $ outDocLn $ text ":$:" <+> ppr clo

                        when shouldPrintTrace 
                         $ do   outDocLn $ checkTraceDoc ct
                                outDoc (text "\n")

                ShowTypeValue
                 ->     outDocLn $ ppr x <+> text "::" <+> ppr t
        
                ShowTypeEffect
                 ->     outDocLn $ ppr x <+> text ":!:" <+> ppr eff

                ShowTypeClosure
                 ->     outDocLn $ ppr x <+> text ":$:" <+> ppr clo

        goResult _ _
         = return ()


-- Recon ----------------------------------------------------------------------
-- | Check expression and reconstruct type annotations on binders.
cmdExpRecon :: Language -> Source -> String -> IO ()
cmdExpRecon language source ss
 | Language bundle      <- language
 , fragment             <- bundleFragment  bundle
 , modules              <- bundleModules   bundle
 =   cmdParseCheckExp fragment modules Recon False True source ss 
 >>= goResult
 where
        goResult (Nothing, _ct)
         = return ()

        goResult (Just x,  _ct)
         = outDocLn $ ppr x


-- Check ----------------------------------------------------------------------
-- | Parse and type-check a core module from a file.
cmdCheckModuleFromFile
        :: (Ord n, Show n, Pretty n, Pretty (err (AnTEC BP.SourcePos n)))
        => Fragment n err
        -> FilePath
        -> ErrorT String IO (Module (AnTEC BP.SourcePos n) n)

cmdCheckModuleFromFile fragment filePath
 = goLoad 
 where  lexModule =  fragmentLexModule fragment filePath 1

        -- Load and type-check the module.
        goLoad 
         = do   mModule <- liftIO 
                        $ loadModuleFromFile 
                                (fragmentProfile fragment) lexModule filePath C.Recon 
                case mModule of
                 (Left  err, _ct) -> throwError (renderIndent $ ppr err)
                 (Right mm,  _ct) -> goCheckFragment mm

        -- Do fragment specific checks.
        goCheckFragment mm
         = case fragmentCheckModule fragment mm of
                Just err          -> throwError (renderIndent $ ppr err)
                Nothing           -> return mm


-- | Parse and type-check a core module from a string.
cmdCheckModuleFromString
        :: (Ord n, Show n, Pretty n, Pretty (err (AnTEC BP.SourcePos n)))
        => Fragment n err       -- ^ Language fragment.
        -> Source               -- ^ Source of the program text.
        -> String               -- ^ Program text.
        -> C.Mode n             -- ^ Type checker mode.
        -> ErrorT String IO (Module (AnTEC BP.SourcePos n) n)

cmdCheckModuleFromString fragment source str mode
 = goLoad
 where  lexModule = fragmentLexModule fragment 
                        (nameOfSource source) 
                        (lineStartOfSource source)

        -- Load and type-check the module.
        goLoad
         = let  mModule = loadModuleFromString
                                (fragmentProfile fragment) lexModule
                                (nameOfSource source) mode str

            in  case mModule of
                  (Left err, _ct) -> throwError (renderIndent $ ppr err)
                  (Right mm, _ct) -> goCheckFragment mm

        goCheckFragment mm
         = case fragmentCheckModule fragment mm of
                Just err        -> throwError  (renderIndent $ ppr err)
                Nothing         -> return mm


-- | Parse a core spec, and return its kind.
cmdParseCheckType 
        :: (Ord n, Show n, Pretty n)
        => Source               -- ^ Source of the program text.
        -> Fragment n err       -- ^ Language fragment.
        -> Universe             -- ^ Universe this type is supposed to be in.
        -> String               -- ^ Program text.
        -> IO (Maybe (Type n, Kind n))

cmdParseCheckType source frag uni str
 = let  srcName = nameOfSource source
        srcLine = lineStartOfSource source
        toks    = fragmentLexExp frag srcName srcLine str
        eTK     = loadType (fragmentProfile frag) uni srcName toks
   in   case eTK of
         Left err       
          -> do outDocLn $ ppr err
                return Nothing

         Right (t, k)
          ->    return $ Just (t, k)


-- | Parse the given core expression, 
--   and return it, along with its type, effect and closure.
--
--   If the expression had a parse error, undefined vars, or type error
--   then print this to the console.
--
--   We include a flag to override the language profile to allow partially
--   applied primitives. Although a paticular evaluator (or backend) may not
--   support partially applied primitives, we want to accept them if we are
--   only loading an expression to check its type.
--
cmdParseCheckExp 
        :: (Ord n, Show n, Pretty n, Pretty (err (AnTEC BP.SourcePos n)))
        => Fragment n err       -- ^ The current language fragment.
        -> ModuleMap (AnTEC () n) n -- ^ Current modules
        -> Mode n               -- ^ Type checker mode.
        -> Bool                 -- ^ Print type checker trace.
        -> Bool                 -- ^ Allow partial application of primitives.
        -> Source               -- ^ Where this expression was sourced from.
        -> String               -- ^ Text to parse.
        -> IO ( Maybe (Exp (AnTEC BP.SourcePos n) n)
              , Maybe CheckTrace)

cmdParseCheckExp 
        frag modules 
        mode printTrace permitPartialPrims 
        source str
 = goLex
 where
        -- Override profile to allow partially applied primitives if we were
        -- told to do so.
        profile   = fragmentProfile frag
        features  = profileFeatures profile
        features' = features { featuresPartialPrims 
                             = featuresPartialPrims features || permitPartialPrims}
        profile'  = profile  { profileFeatures  = features' }
        frag'     = frag     { fragmentProfile  = profile'  }

        goLex 
         = goLoad (fragmentLexExp frag'
                        (nameOfSource source) 
                        (lineStartOfSource source) 
                        str)

        -- Parse and type check the expression.
        goLoad toks
         = case loadExp profile' modules (nameOfSource source) mode toks of
              (Left err, mct)
               -> do    outDocLn $ ppr err
                        
                        case mct of
                         Just ct 
                          | printTrace  -> outDocLn $ ppr ct
                         _              -> return ()
                        
                        return (Nothing, mct)

              (Right result, mct)
               -> goCheckFragment mct result

        -- Do fragment specific checks.
        goCheckFragment ct x
         = case fragmentCheckExp frag' x of
             Just err 
              -> do     putStrLn $ renderIndent $ ppr err
                        return (Nothing, ct)

             Nothing  
              -> do     return (Just x,  ct)

