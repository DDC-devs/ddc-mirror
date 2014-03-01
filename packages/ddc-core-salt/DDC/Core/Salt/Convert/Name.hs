
module DDC.Core.Salt.Convert.Name
        ( sanitizeName
        , sanitizeGlobal
        , sanitizeLocal)
where
import Data.Maybe


-- | Rewrite the symbols in a name to make it safe to export as an external
--   symbol. For example, a names containing a '&' is prefixed with '_sym_'
--   and the '&' replzced by 'ZAn'. Literal 'Z's in a symbolic name are doubled
--   to 'ZZ'.
sanitizeName :: String -> String
sanitizeName str
 = let  hasSymbols      = any isJust $ map convertSymbol str
   in   if hasSymbols
         then "_sym_" ++ concatMap rewriteChar str
         else str


-- | Like 'sanitizeGlobal' but indicate that the name is going to be visible
--   globally.
sanitizeGlobal :: String -> String
sanitizeGlobal = sanitizeName


-- | Like 'sanitizeName' but at add an extra '_' prefix.
--   This is used for function-local names so that they do not conflict 
--   with globally-visible ones.
sanitizeLocal  :: String -> String
sanitizeLocal str
 = "_" ++ sanitizeGlobal str


-- | Get the encoded version of a character.
rewriteChar :: Char -> String
rewriteChar c
        | Just str <- convertSymbol c      = "Z" ++ str
        | 'Z'      <- c                    = "ZZ"
        | otherwise                        = [c]


-- | Convert symbols to their sanitized form.
convertSymbol :: Char -> Maybe String
convertSymbol c
 = case c of
        '!'     -> Just "Bg"
        '@'     -> Just "At"
        '#'     -> Just "Hs"
        '$'     -> Just "Dl"
        '%'     -> Just "Pc"
        '^'     -> Just "Ht"
        '&'     -> Just "An"
        '*'     -> Just "St"
        '~'     -> Just "Tl"
        '-'     -> Just "Ms"
        '+'     -> Just "Ps"
        '='     -> Just "Eq"
        '|'     -> Just "Pp"
        '\\'    -> Just "Bs"
        '/'     -> Just "Fs"
        ':'     -> Just "Cl"
        '.'     -> Just "Dt"
        '?'     -> Just "Qm"
        '<'     -> Just "Lt"
        '>'     -> Just "Gt"
        '['     -> Just "Br"
        ']'     -> Just "Kt"
        '\''    -> Just "Pm"
        '`'     -> Just "Bt"
        _       -> Nothing

