{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Cardano.CLI.Legacy.Run.Transaction
  ( runLegacyTransactionCmds
  ) where

import           Cardano.Api
import qualified Cardano.Api.Byron as Api

import qualified Cardano.CLI.EraBased.Commands.Transaction as Cmd
import           Cardano.CLI.EraBased.Run.Transaction
import           Cardano.CLI.Legacy.Commands.Transaction
import           Cardano.CLI.Types.Common
import           Cardano.CLI.Types.Errors.TxCmdError
import           Cardano.CLI.Types.Errors.TxValidationError
import           Cardano.CLI.Types.Governance

import           Control.Monad.Trans.Class
import           Control.Monad.Trans.Except
import           Control.Monad.Trans.Except.Extra
import           Data.Function

runLegacyTransactionCmds :: LegacyTransactionCmds -> ExceptT TxCmdError IO ()
runLegacyTransactionCmds = \case
  TransactionBuildCmd mNodeSocketPath era consensusModeParams nid mScriptValidity mOverrideWits txins readOnlyRefIns
            reqSigners txinsc mReturnColl mTotCollateral txouts changeAddr mValue mLowBound
            mUpperBound certs wdrls metadataSchema scriptFiles metadataFiles mUpProp mconwayVote
            mNewConstitution outputOptions -> do
      runLegacyTransactionBuildCmd mNodeSocketPath era consensusModeParams nid mScriptValidity mOverrideWits txins readOnlyRefIns
            reqSigners txinsc mReturnColl mTotCollateral txouts changeAddr mValue mLowBound
            mUpperBound certs wdrls metadataSchema scriptFiles metadataFiles mUpProp mconwayVote
            mNewConstitution outputOptions
  TransactionBuildRawCmd era mScriptValidity txins readOnlyRefIns txinsc mReturnColl
               mTotColl reqSigners txouts mValue mLowBound mUpperBound fee certs wdrls
               metadataSchema scriptFiles metadataFiles mProtocolParamsFile mUpProp out -> do
      runLegacyTransactionBuildRawCmd era mScriptValidity txins readOnlyRefIns txinsc mReturnColl
               mTotColl reqSigners txouts mValue mLowBound mUpperBound fee certs wdrls
               metadataSchema scriptFiles metadataFiles mProtocolParamsFile mUpProp out
  TransactionSignCmd txinfile skfiles network txoutfile ->
      runLegacyTransactionSignCmd txinfile skfiles network txoutfile
  TransactionSubmitCmd mNodeSocketPath consensusModeParams network txFp ->
      runLegacyTransactionSubmitCmd mNodeSocketPath consensusModeParams network txFp
  TransactionCalculateMinFeeCmd txbody nw pParamsFile nInputs nOutputs nShelleyKeyWitnesses nByronKeyWitnesses ->
      runLegacyTransactionCalculateMinFeeCmd txbody nw pParamsFile nInputs nOutputs nShelleyKeyWitnesses nByronKeyWitnesses
  TransactionCalculateMinValueCmd (EraInEon sbe) pParamsFile txOuts' ->
      runLegacyTransactionCalculateMinValueCmd (AnyShelleyBasedEra sbe) pParamsFile txOuts'
  TransactionHashScriptDataCmd scriptDataOrFile ->
      runLegacyTransactionHashScriptDataCmd scriptDataOrFile
  TransactionTxIdCmd txinfile ->
      runLegacyTransactionTxIdCmd txinfile
  TransactionViewCmd yamlOrJson mOutFile txinfile ->
      runLegacyTransactionViewCmd yamlOrJson mOutFile txinfile
  TransactionPolicyIdCmd sFile ->
      runLegacyTransactionPolicyIdCmd sFile
  TransactionWitnessCmd txBodyfile witSignData mbNw outFile ->
      runLegacyTransactionWitnessCmd txBodyfile witSignData mbNw outFile
  TransactionSignWitnessCmd txBodyFile witnessFile outFile ->
      runLegacyTransactionSignWitnessCmd txBodyFile witnessFile outFile

-- ----------------------------------------------------------------------------
-- Building transactions
--

runLegacyTransactionBuildCmd :: ()
  => SocketPath
  -> EraInEon ShelleyBasedEra
  -> ConsensusModeParams
  -> NetworkId
  -> Maybe ScriptValidity
  -> Maybe Word -- ^ Override the required number of tx witnesses
  -> [(TxIn, Maybe (ScriptWitnessFiles WitCtxTxIn))] -- ^ Transaction inputs with optional spending scripts
  -> [TxIn] -- ^ Read only reference inputs
  -> [RequiredSigner] -- ^ Required signers
  -> [TxIn] -- ^ Transaction inputs for collateral, only key witnesses, no scripts.
  -> Maybe TxOutShelleyBasedEra -- ^ Return collateral
  -> Maybe Lovelace -- ^ Total collateral
  -> [TxOutAnyEra]
  -> TxOutChangeAddress
  -> Maybe (Value, [ScriptWitnessFiles WitCtxMint])
  -> Maybe SlotNo -- ^ Validity lower bound
  -> Maybe SlotNo -- ^ Validity upper bound
  -> [(CertificateFile, Maybe (ScriptWitnessFiles WitCtxStake))]
  -> [(StakeAddress, Lovelace, Maybe (ScriptWitnessFiles WitCtxStake))] -- ^ Withdrawals with potential script witness
  -> TxMetadataJsonSchema
  -> [ScriptFile]
  -> [MetadataFile]
  -> Maybe UpdateProposalFile
  -> [VoteFile In]
  -> [ProposalFile In]
  -> TxBuildOutputOptions
  -> ExceptT TxCmdError IO ()
runLegacyTransactionBuildCmd
    socketPath (EraInEon sbe)
    consensusModeParams nid mScriptValidity mOverrideWits txins readOnlyRefIns
    reqSigners txinsc mReturnColl mTotCollateral txouts changeAddr mValue mLowBound
    mUpperBound certs wdrls metadataSchema scriptFiles metadataFiles mUpdateProposal voteFiles
    proposalFiles outputOptions = do

  mfUpdateProposalFile <-
    validateUpdateProposalFile (shelleyBasedToCardanoEra sbe) mUpdateProposal
      & hoistEither
      & firstExceptT TxCmdTxUpdateProposalValidationError

  let upperBound = TxValidityUpperBound sbe mUpperBound

  runTransactionBuildCmd
    ( Cmd.TransactionBuildCmdArgs sbe socketPath
        consensusModeParams nid mScriptValidity mOverrideWits txins readOnlyRefIns
        reqSigners txinsc mReturnColl mTotCollateral txouts changeAddr mValue mLowBound
        upperBound certs wdrls metadataSchema scriptFiles metadataFiles mfUpdateProposalFile voteFiles
        proposalFiles outputOptions
    )

-- TODO: Neither QA nor Sam is using `cardano-cli byron transaction build-raw`
-- for Byron era transactions. So we can parameterize this function on ShelleyBasedEra.
-- They are using `issue-utxo-expenditure`. However we will deprecate it in a follow up PR.
-- TODO: As a follow up we need to expose a simple tx building command that only
-- uses inputs, outputs and update proposals. NB: Update proposals are a separate
-- thing in the Byron era so we need to figure out how we are handling that at the
-- cli command level.
runLegacyTransactionBuildRawCmd :: ()
  => AnyCardanoEra
  -> Maybe ScriptValidity
  -> [(TxIn, Maybe (ScriptWitnessFiles WitCtxTxIn))]
  -> [TxIn] -- ^ Read only reference inputs
  -> [TxIn] -- ^ Transaction inputs for collateral, only key witnesses, no scripts.
  -> Maybe TxOutShelleyBasedEra -- ^ Return collateral
  -> Maybe Lovelace -- ^ Total collateral
  -> [RequiredSigner]
  -> [TxOutAnyEra]
  -> Maybe (Value, [ScriptWitnessFiles WitCtxMint]) -- ^ Multi-Asset value with script witness
  -> Maybe SlotNo -- ^ Validity lower bound
  -> Maybe SlotNo -- ^ Validity upper bound
  -> Maybe Lovelace -- ^ Tx fee
  -> [(CertificateFile, Maybe (ScriptWitnessFiles WitCtxStake))]
  -> [(StakeAddress, Lovelace, Maybe (ScriptWitnessFiles WitCtxStake))]
  -> TxMetadataJsonSchema
  -> [ScriptFile]
  -> [MetadataFile]
  -> Maybe ProtocolParamsFile
  -> Maybe UpdateProposalFile
  -> TxBodyFile Out
  -> ExceptT TxCmdError IO ()
runLegacyTransactionBuildRawCmd (AnyCardanoEra ByronEra) _ txins _ _ _
    _ _ txouts _ _ _ _ _ _
    _ _ _ _ _
    outFile = do
      let apiTxIns = [ ( txIn, BuildTxWith (KeyWitness KeyWitnessForSpending)) | (txIn, _) <- txins]
      byronOuts <- mapM toTxOutByronEra txouts
      case makeByronTransactionBody apiTxIns byronOuts of
        Left err -> error $ "Error occurred while creating a Byron based UTxO transaction: " <> show err
        Right txBody -> do
          let noWitTx = makeSignedByronTransaction [] txBody
          lift (Api.writeByronTxFileTextEnvelopeCddl outFile noWitTx)
            & onLeft (left . TxCmdWriteFileError)

runLegacyTransactionBuildRawCmd
    (AnyCardanoEra era) mScriptValidity txins readOnlyRefIns txinsc mReturnColl
    mTotColl reqSigners txouts mValue mLowBound mUpperBound fee certs wdrls
    metadataSchema scriptFiles metadataFiles mProtocolParamsFile mUpdateProposal
    outFile = do

  caseByronOrShelleyBasedEra
    (error "runLegacyTransactionBuildRawCmd: This should be impossible")
    (\sbe -> do
       mfUpdateProposalFile <- validateUpdateProposalFile era mUpdateProposal
                                 & hoistEither
                                 & firstExceptT TxCmdTxUpdateProposalValidationError

       let upperBound = TxValidityUpperBound sbe mUpperBound

       runTransactionBuildRawCmd
         ( Cmd.TransactionBuildRawCmdArgs
             sbe mScriptValidity txins readOnlyRefIns txinsc mReturnColl
             mTotColl reqSigners txouts mValue mLowBound upperBound fee certs wdrls
             metadataSchema scriptFiles metadataFiles mProtocolParamsFile mfUpdateProposalFile [] []
             outFile
         )
         )
    era


runLegacyTransactionSignCmd :: InputTxBodyOrTxFile
          -> [WitnessSigningData]
          -> Maybe NetworkId
          -> TxFile Out
          -> ExceptT TxCmdError IO ()
runLegacyTransactionSignCmd
    txOrTxBody
    witSigningData
    mnw
    outTxFile =
  runTransactionSignCmd
    ( Cmd.TransactionSignCmdArgs
       txOrTxBody
       witSigningData
       mnw
       outTxFile
    )

runLegacyTransactionSubmitCmd :: ()
  => SocketPath
  -> ConsensusModeParams
  -> NetworkId
  -> FilePath
  -> ExceptT TxCmdError IO ()
runLegacyTransactionSubmitCmd
    socketPath
    consensusModeParams
    network
    txFilePath =
  runTransactionSubmitCmd
    ( Cmd.TransactionSubmitCmdArgs
        socketPath
        consensusModeParams
        network
        txFilePath
     )

runLegacyTransactionCalculateMinFeeCmd :: ()
  => TxBodyFile In
  -> NetworkId
  -> ProtocolParamsFile
  -> TxInCount
  -> TxOutCount
  -> TxShelleyWitnessCount
  -> TxByronWitnessCount
  -> ExceptT TxCmdError IO ()
runLegacyTransactionCalculateMinFeeCmd
    txbodyFile
    nw
    pParamsFile
    txInCount
    txOutCount
    txShelleyWitnessCount
    txByronWitnessCount =
  runTransactionCalculateMinFeeCmd
    ( Cmd.TransactionCalculateMinFeeCmdArgs
        txbodyFile
        nw
        pParamsFile
        txInCount
        txOutCount
        txShelleyWitnessCount
        txByronWitnessCount
    )

runLegacyTransactionCalculateMinValueCmd :: ()
  => AnyShelleyBasedEra
  -> ProtocolParamsFile
  -> TxOutShelleyBasedEra
  -> ExceptT TxCmdError IO ()
runLegacyTransactionCalculateMinValueCmd
    (AnyShelleyBasedEra era)
    pParamsFile
    txOut =
  runTransactionCalculateMinValueCmd
    ( Cmd.TransactionCalculateMinValueCmdArgs
        era
        pParamsFile
        txOut
    )

runLegacyTransactionPolicyIdCmd ::  ScriptFile -> ExceptT TxCmdError IO ()
runLegacyTransactionPolicyIdCmd scriptFile =
  runTransactionPolicyIdCmd
    ( Cmd.TransactionPolicyIdCmdArgs
        scriptFile
    )

runLegacyTransactionHashScriptDataCmd :: ScriptDataOrFile -> ExceptT TxCmdError IO ()
runLegacyTransactionHashScriptDataCmd scriptDataOrFile =
  runTransactionHashScriptDataCmd
    ( Cmd.TransactionHashScriptDataCmdArgs
        scriptDataOrFile
    )

runLegacyTransactionTxIdCmd :: InputTxBodyOrTxFile -> ExceptT TxCmdError IO ()
runLegacyTransactionTxIdCmd txfile =
  runTransactionTxIdCmd
    ( Cmd.TransactionTxIdCmdArgs
        txfile
    )

runLegacyTransactionViewCmd :: ViewOutputFormat -> Maybe (File () Out) -> InputTxBodyOrTxFile -> ExceptT TxCmdError IO ()
runLegacyTransactionViewCmd
    yamlOrJson
    mOutFile
    inputTxBodyOrTxFile =
  runTransactionViewCmd
    ( Cmd.TransactionViewCmdArgs
        yamlOrJson
        mOutFile
        inputTxBodyOrTxFile
    )

runLegacyTransactionWitnessCmd :: ()
  => TxBodyFile In
  -> WitnessSigningData
  -> Maybe NetworkId
  -> File () Out
  -> ExceptT TxCmdError IO ()
runLegacyTransactionWitnessCmd
    txbodyFile
    witSignData
    mbNw
    outFile =
  runTransactionWitnessCmd
    ( Cmd.TransactionWitnessCmdArgs
        txbodyFile
        witSignData
        mbNw
        outFile
     )

runLegacyTransactionSignWitnessCmd :: ()
  => TxBodyFile In
  -> [WitnessFile]
  -> File () Out
  -> ExceptT TxCmdError IO ()
runLegacyTransactionSignWitnessCmd
    txbodyFile
    witnessFiles
    outFile =
  runTransactionSignWitnessCmd
    ( Cmd.TransactionSignWitnessCmdArgs
        txbodyFile
        witnessFiles
        outFile
    )
