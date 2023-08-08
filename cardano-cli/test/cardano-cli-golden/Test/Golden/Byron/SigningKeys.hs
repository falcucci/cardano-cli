{-# LANGUAGE OverloadedStrings #-}

module Test.Golden.Byron.SigningKeys
  ( hprop_deserialise_legacy_signing_Key
  , hprop_deserialise_nonLegacy_signing_Key
  , hprop_deserialise_NonLegacy_Signing_Key_API
  , hprop_deserialiseLegacy_Signing_Key_API
  , hprop_generate_and_read_nonlegacy_signingkeys
  , hprop_migrate_legacy_to_nonlegacy_signingkeys
  , hprop_print_legacy_signing_key_address
  , hprop_print_nonLegacy_signing_key_address
  ) where

import           Cardano.Api.Byron

import           Cardano.CLI.Byron.Key (readByronSigningKey)
import           Cardano.CLI.Byron.Legacy (decodeLegacyDelegateKey)
import           Cardano.CLI.Commands.Legacy
import qualified Cardano.Crypto.Signing as Crypto

import           Codec.CBOR.Read (deserialiseFromBytes)
import           Control.Monad (void)
import           Control.Monad.Trans.Except (runExceptT)
import qualified Data.ByteString.Lazy as LB

import           Test.Cardano.CLI.Util

import           Hedgehog (Property, property, success)
import qualified Hedgehog as H
import qualified Hedgehog.Extras.Test.Base as H
import           Hedgehog.Internal.Property (failWith)

hprop_deserialise_legacy_signing_Key :: Property
hprop_deserialise_legacy_signing_Key = propertyOnce $ do
  legSkeyBs <- H.evalIO $ LB.readFile "test/cardano-cli-golden/files/golden/byron/keys/legacy.skey"
  case deserialiseFromBytes decodeLegacyDelegateKey legSkeyBs of
    Left deSerFail -> failWith Nothing $ show deSerFail
    Right _ -> success

hprop_deserialise_nonLegacy_signing_Key :: Property
hprop_deserialise_nonLegacy_signing_Key = propertyOnce $ do
  skeyBs <- H.evalIO $ LB.readFile "test/cardano-cli-golden/files/golden/byron/keys/byron.skey"
  case deserialiseFromBytes Crypto.fromCBORXPrv skeyBs of
    Left deSerFail -> failWith Nothing $ show deSerFail
    Right _ -> success

hprop_print_legacy_signing_key_address :: Property
hprop_print_legacy_signing_key_address = propertyOnce $ do
  let legKeyFp = "test/cardano-cli-golden/files/golden/byron/keys/legacy.skey"

  void $ execCardanoCLI
   [ "signing-key-address", "--byron-legacy-formats"
   , "--testnet-magic", "42"
   , "--secret", legKeyFp
   ]

  void $ execCardanoCLI
   [ "signing-key-address", "--byron-legacy-formats"
   , "--mainnet"
   , "--secret", legKeyFp
   ]

hprop_print_nonLegacy_signing_key_address :: Property
hprop_print_nonLegacy_signing_key_address = propertyOnce $ do
  let nonLegKeyFp = "test/cardano-cli-golden/files/golden/byron/keys/byron.skey"

  void $ execCardanoCLI
   [ "signing-key-address", "--byron-formats"
   , "--testnet-magic", "42"
   , "--secret", nonLegKeyFp
   ]

  void $ execCardanoCLI
   [ "signing-key-address", "--byron-formats"
   , "--mainnet"
   , "--secret", nonLegKeyFp
   ]

hprop_generate_and_read_nonlegacy_signingkeys :: Property
hprop_generate_and_read_nonlegacy_signingkeys = property $ do
  byronSkey <- H.evalIO $ generateSigningKey AsByronKey
  case deserialiseFromRawBytes (AsSigningKey AsByronKey) (serialiseToRawBytes byronSkey) of
    Left _ -> failWith Nothing "Failed to deserialise non-legacy Byron signing key. "
    Right _ -> success

hprop_migrate_legacy_to_nonlegacy_signingkeys :: Property
hprop_migrate_legacy_to_nonlegacy_signingkeys =
  propertyOnce . H.moduleWorkspace "tmp" $ \tempDir -> do
    let legKeyFp = "test/cardano-cli-golden/files/golden/byron/keys/legacy.skey"
    nonLegacyKeyFp <- noteTempFile tempDir "nonlegacy.skey"

    void $ execCardanoCLI
     [ "migrate-delegate-key-from"
     , "--from", legKeyFp
     , "--to", nonLegacyKeyFp
     ]

    eSignKey <- H.evalIO . runExceptT . readByronSigningKey NonLegacyByronKeyFormat
                  $ File nonLegacyKeyFp

    case eSignKey of
      Left err -> failWith Nothing $ show err
      Right _ -> success

hprop_deserialise_NonLegacy_Signing_Key_API :: Property
hprop_deserialise_NonLegacy_Signing_Key_API = propertyOnce $ do
  eFailOrWit <- H.evalIO . runExceptT $ readByronSigningKey NonLegacyByronKeyFormat "test/cardano-cli-golden/files/golden/byron/keys/byron.skey"
  case eFailOrWit of
    Left keyFailure -> failWith Nothing $ show keyFailure
    Right _ -> success

hprop_deserialiseLegacy_Signing_Key_API :: Property
hprop_deserialiseLegacy_Signing_Key_API = propertyOnce $ do
  eFailOrWit <- H.evalIO . runExceptT $ readByronSigningKey LegacyByronKeyFormat "test/cardano-cli-golden/files/golden/byron/keys/legacy.skey"
  case eFailOrWit of
    Left keyFailure -> failWith Nothing $ show keyFailure
    Right _ -> success
