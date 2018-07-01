
module DDC.Core.Interface
        ( Interface     (..)
        , Store         (..)
        , Meta          (..)
        , Error         (..)

        , new, wrap, load
        , getMeta
        , getModuleNames
        , getInterfaces
        , findImportValue
        , importValuesOfStore)
where
import DDC.Core.Interface.Store
import DDC.Core.Interface.Error
import DDC.Core.Interface.Base