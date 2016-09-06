
module DDC.Driver.Output
        ( outDoc, outDocLn
        , outStr, outStrLn
        , chatStrLn)
where
import DDC.Data.Pretty


-- | Output a document to the console.
outDoc :: Doc -> IO ()
outDoc doc
        = putDoc   RenderIndent doc

-- | Output a document and newline to the console.
outDocLn :: Doc -> IO ()
outDocLn doc
        = putDocLn RenderIndent doc


-- | Output a string to the console.
outStr :: String -> IO ()
outStr str
        = putStr str


-- | Output a string and newline to the console.
outStrLn :: String -> IO ()
outStrLn str
        = putStrLn str


-- | Output chatty 'ok' type responses.
--   These are only displayed in the Interactive and Batch interfaces.
chatStrLn :: String -> IO ()
chatStrLn str
        = putStrLn str
