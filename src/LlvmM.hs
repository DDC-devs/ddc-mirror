module LlvmM
	( LlvmState
	, LlvmM
	, addBlock
	, addBlockResult
	, addComment
	, currentReg

	, addAlias

	, addGlobalVar
	, addGlobalFuncDecl

	, newUniqueReg
	, newUniqueNamedReg
	, newUniqueLabel
	, newUniqueName
	, newNamedReg

	, initLlvmState

	, startFunction
	, endFunction

	, setTags
	, getTag

	, renderModule )
where

import DDC.Main.Error

import Util

import Llvm
import Llvm.GhcReplace.Unique
import Llvm.Util

import qualified Data.Map		as Map


stage = "LlvmM"


data LlvmState
	= LS
	-- Two temporary variables to hold the current 'of interest' register
	-- and a list of blocks of statements. The blocks of statements are
	-- pushed onto the head of the list and when all statements for a
	-- function are available, the list of blocks is reversed and
	-- concatenated to produce a list of statements, which can then be
	-- pushed onto the functions list below.
	{ tmpReg	:: Maybe LlvmVar
	, tmpBlocks	:: [[LlvmStatement]]

	-- | Aliases used in the module.
	, aliases	:: Map String LlvmType

	-- | Global variables for the module.
	, globVars	:: [LMGlobal]
	-- | Forward declarations of external functions.
	, funcDecls	:: Map String LlvmFunctionDecl

	-- | Functions defined in this module.
	, functions	:: [LlvmFunction]

	-- | The constructor tags for the module.
	, ctorTags	:: Map String Int }

type LlvmM = StateT LlvmState IO


initLlvmState :: LlvmState
initLlvmState
 = LS	{ tmpReg	= Nothing
	, tmpBlocks	= []

	, aliases	= Map.empty
	, globVars	= []
	, funcDecls	= Map.empty
	, functions	= []
	, ctorTags	= Map.empty }


addBlock :: [LlvmStatement] -> LlvmM ()
addBlock code
 = do	state	<- get
	modify $ \s -> s
		{ tmpReg = Nothing
		, tmpBlocks = code : (tmpBlocks state) }


addBlockResult :: LlvmVar -> [LlvmStatement] -> LlvmM ()
addBlockResult result code
 = do	state	<- get
	modify $ \s -> s
		{ tmpReg = Just result
		, tmpBlocks = code : (tmpBlocks state) }


addComment :: LMString -> LlvmM ()
addComment text
 = do	state	<- get
	modify $ \s -> s
		{ tmpReg = tmpReg state
		, tmpBlocks = [Comment (lines text)] : (tmpBlocks state) }


addGlobalVar :: LMGlobal -> LlvmM ()
addGlobalVar gvar
 = do	state	<- get
	modify $ \s -> s { globVars = gvar : (globVars state) }


currentReg :: LlvmM LlvmVar
currentReg
 = do	state	<- get
	return $ fromJust $ tmpReg state


startFunction :: LlvmM ()
startFunction
 =	modify $ \s -> s { tmpReg = Nothing, tmpBlocks = [] }


endFunction :: LlvmFunctionDecl -> [LMString] -> [LlvmFuncAttr] -> LMSection -> LlvmM ()
endFunction funcDecl funcArgs funcAttrs funcSect
 = do	-- At end of function reverse the list of blocks and then
	-- concatenate the blocks to produce a list of statements.
	state		<- get
	let fblks	= tmpBlocks state
	let blks	=
			if null fblks
			  then [Return Nothing]
			  else concat $ reverse $
				case last (head fblks) of
				  Return _	-> fblks
				  _		-> [Return Nothing] : fblks

	let func	= LlvmFunction funcDecl funcArgs funcAttrs funcSect
				[ LlvmBlock (fakeUnique "entry") blks ]

	modify $ \s -> s { functions = func : (functions s) }

--------------------------------------------------------------------------------

addAlias :: LlvmAlias -> LlvmM ()
addAlias (name, typ)
 = do	state		<- get
	let map		= aliases state
	case Map.lookup name map of
	  Nothing	-> modify $ \s -> s { aliases = Map.insert name typ map }
	  Just curr	-> if curr == typ
				then return ()
				else panic stage
					$ "The following two should match :"
					++ "\n    " ++ show curr
					++ "\n    " ++ show typ


addGlobalFuncDecl :: LlvmFunctionDecl -> LlvmM ()
addGlobalFuncDecl fd
 = do	state		<- get
	let map		= funcDecls state
	let name	= nameOfFunDecl fd
	case Map.lookup name map of
	  Nothing	-> modify $ \s -> s { funcDecls = Map.insert name fd map }
	  Just curr	-> if curr == fd
				then return ()
				else panic stage
					$ "The following two should match :"
					++ "\n    " ++ show curr
					++ "\n    " ++ show fd

--------------------------------------------------------------------------------

setTags :: [(String, Int)] -> LlvmM ()
setTags lst
 = do	state		<- get
	let ctors	= ctorTags state
	modify		$ \s -> s { ctorTags = foldl' insertTag ctors lst }

insertTag :: Map String Int -> (String, Int) -> Map String Int
insertTag map (name, value)
 = case Map.lookup name map of
	Nothing	-> Map.insert name value map
	Just v	-> if value == v
			then map
			else panic stage
				$ "Ctor name mismatch for '" ++ name ++ "' :"
					++ "\n    " ++ show value
					++ "\n    " ++ show v

getTag :: String -> LlvmM Int
getTag name
 = do	state		<- get
	let ctors	= ctorTags state
	case Map.lookup name ctors of
	  Just v	-> return v
	  Nothing	-> panic stage $ "Can't find Ctor tag '" ++ name ++ "'."

--------------------------------------------------------------------------------

renderModule :: [LMString] ->  LlvmM LlvmModule
renderModule comments
 = do	state		<- get
	let globals	= globVars state
	let taliases	= Map.toList $ aliases state
	let fdecls	= map snd $ Map.toList $ funcDecls state
	return	$ LlvmModule comments taliases globals fdecls
				$ reverse $ functions state

--------------------------------------------------------------------------------

-- | Generate a new unique register variable with the specified LlvmType.
newUniqueReg :: LlvmType -> LlvmM LlvmVar
newUniqueReg t
 = do	u <- lift $ newUnique "r"
	return $ LMLocalVar u t


-- | Generate a new unique named register variable with the specified LlvmType.
newUniqueNamedReg :: String -> LlvmType -> LlvmM LlvmVar
newUniqueNamedReg name t
 = do	u <- lift $ newUnique name
	return $ LMLocalVar u t


-- | Generate a new unique register variable.
newUniqueLabel :: String -> LlvmM LlvmVar
newUniqueLabel label
 = do	u <- lift $ newUnique label
	return $ LMLocalVar u LMLabel


newUniqueName :: String -> LlvmM String
newUniqueName name
 = do	u <- lift $ newUnique name
	return $ show u

newNamedReg :: String -> LlvmType -> LlvmM LlvmVar
newNamedReg name t
 =	return $ LMLocalVar (fakeUnique name) t


