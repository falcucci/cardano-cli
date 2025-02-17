{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE LambdaCase #-}

module Cardano.CLI.EraBased.Commands.Governance.DRep
  ( GovernanceDRepCmds (..)
  , renderGovernanceDRepCmds

  , GovernanceDRepKeyGenCmdArgs(..)
  , GovernanceDRepIdCmdArgs(..)
  , GovernanceDRepRegistrationCertificateCmdArgs(..)
  , GovernanceDRepRetirementCertificateCmdArgs(..)
  , GovernanceDRepMetadataHashCmdArgs(..)
  )
where

import           Cardano.Api
import qualified Cardano.Api.Ledger as Ledger
import           Cardano.Api.Shelley

import           Cardano.CLI.Types.Common
import           Cardano.CLI.Types.Key

import           Data.Text (Text)

data GovernanceDRepCmds era
  = GovernanceDRepKeyGenCmd                   !(GovernanceDRepKeyGenCmdArgs era)
  | GovernanceDRepIdCmd                       !(GovernanceDRepIdCmdArgs era)
  | GovernanceDRepRegistrationCertificateCmd  !(GovernanceDRepRegistrationCertificateCmdArgs era)
  | GovernanceDRepRetirementCertificateCmd    !(GovernanceDRepRetirementCertificateCmdArgs era)
  | GovernanceDRepMetadataHashCmd             !(GovernanceDRepMetadataHashCmdArgs era)

data GovernanceDRepKeyGenCmdArgs era =
  GovernanceDRepKeyGenCmdArgs
    { eon       :: !(ConwayEraOnwards era)
    , vkeyFile  :: !(File (VerificationKey ()) Out)
    , skeyFile  :: !(File (SigningKey ()) Out)
    }

data GovernanceDRepIdCmdArgs era =
  GovernanceDRepIdCmdArgs
    { eon             :: !(ConwayEraOnwards era)
    , vkeySource      :: !(VerificationKeyOrFile DRepKey)
    , idOutputFormat  :: !IdOutputFormat
    , mOutFile        :: !(Maybe (File () Out))
    }

data GovernanceDRepRegistrationCertificateCmdArgs era =
  GovernanceDRepRegistrationCertificateCmdArgs
    { eon                 :: !(ConwayEraOnwards era)
    , drepHashSource      :: !DRepHashSource
    , deposit             :: !Lovelace
    , mAnchor             :: !(Maybe (Ledger.Anchor (Ledger.EraCrypto (ShelleyLedgerEra era))))
    , outFile             :: !(File () Out)
    }

data GovernanceDRepRetirementCertificateCmdArgs era =
  GovernanceDRepRetirementCertificateCmdArgs
    { eon             :: !(ConwayEraOnwards era)
    , vkeyHashSource  :: !(VerificationKeyOrHashOrFile DRepKey)
    , deposit         :: !Lovelace
    , outFile         :: !(File () Out)
    }

data GovernanceDRepMetadataHashCmdArgs era =
  GovernanceDRepMetadataHashCmdArgs
    { eon           :: !(ConwayEraOnwards era)
    , metadataFile  :: !(DRepMetadataFile In)
    , mOutFile      :: !(Maybe (File () Out))
    }

renderGovernanceDRepCmds :: ()
  => GovernanceDRepCmds era
  -> Text
renderGovernanceDRepCmds = \case
  GovernanceDRepKeyGenCmd {} ->
    "governance drep key-gen"
  GovernanceDRepIdCmd {} ->
    "governance drep id"
  GovernanceDRepRegistrationCertificateCmd {} ->
    "governance drep registration-certificate"
  GovernanceDRepRetirementCertificateCmd {} ->
    "governance drep retirement-certificate"
  GovernanceDRepMetadataHashCmd {} ->
    "governance drep metadata-hash"
