{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}

module Cardano.CLI.Types.Errors.QueryCmdLocalStateQueryError
  ( QueryCmdLocalStateQueryError(..)
  , mkEraMismatchError
  ) where

import           Cardano.Api (Error (..))
import           Cardano.Api.Pretty

import           Cardano.CLI.Types.Errors.NodeEraMismatchError
import           Ouroboros.Consensus.Cardano.Block (EraMismatch (..))

import           Prettyprinter ((<+>))

-- | An error that can occur while querying a node's local state.
newtype QueryCmdLocalStateQueryError
  = EraMismatchError EraMismatch
  -- ^ A query from a certain era was applied to a ledger from a different era.
  deriving (Eq, Show)

mkEraMismatchError :: NodeEraMismatchError -> QueryCmdLocalStateQueryError
mkEraMismatchError NodeEraMismatchError{nodeEra, era} =
  EraMismatchError EraMismatch{ ledgerEraName = docToText $ pretty nodeEra
                              , otherEraName = docToText $ pretty era}

instance Error QueryCmdLocalStateQueryError where
  prettyError = \case
    EraMismatchError EraMismatch{ledgerEraName, otherEraName} ->
      "A query from" <+> pretty otherEraName <+> "era was applied to a ledger from a different era:" <+> pretty ledgerEraName
