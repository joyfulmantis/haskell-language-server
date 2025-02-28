{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings  #-}

module Ide.Plugin.Splice.Types where

import           Data.Aeson                  (FromJSON, ToJSON)
import qualified Data.Text                   as T
 -- This import is needed for the ToJSON/FromJSON instances of RealSrcSpan
import           Development.IDE             ()
import           Development.IDE.GHC.Compat  (RealSrcSpan)
import           GHC.Generics                (Generic)
import           Ide.Types                   (CommandId)
import           Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier)

-- | Parameter for the addMethods PluginCommand.
data ExpandSpliceParams = ExpandSpliceParams
    { verTxtDocId   :: VersionedTextDocumentIdentifier
    , spliceSpan    :: RealSrcSpan
    , spliceContext :: SpliceContext
    }
    deriving (Show, Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- FIXME: HsDecl needs different treatment of splicing.
data SpliceContext = Expr | HsDecl | Pat | HsType
    deriving (Read, Show, Eq, Ord, Generic)
    deriving anyclass (ToJSON, FromJSON)

data ExpandStyle = Inplace | Commented
    deriving (Read, Show, Eq, Ord, Generic)

expandStyles :: [(ExpandStyle, (T.Text, CommandId))]
expandStyles =
    [ (Inplace, (inplaceCmdName, expandInplaceId))
    -- , (Commented, commentedCmdName, expandCommentedId)
    ]

toExpandCmdTitle :: ExpandStyle -> T.Text
toExpandCmdTitle Inplace   = inplaceCmdName
toExpandCmdTitle Commented = commentedCmdName

toCommandId :: ExpandStyle -> CommandId
toCommandId Inplace   = expandInplaceId
toCommandId Commented = expandCommentedId

expandInplaceId, expandCommentedId :: CommandId
expandInplaceId = "expandTHSpliceInplace"
expandCommentedId = "expandTHSpliceCommented"

inplaceCmdName :: T.Text
inplaceCmdName = "expand TemplateHaskell Splice (in-place)"

commentedCmdName :: T.Text
commentedCmdName = "expand TemplateHaskell Splice (commented-out)"
