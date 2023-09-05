{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Cardano.CLI.EraBased.Run.Key
  ( runConvertByronGenesisVerificationKeyCmd
  , runConvertByronKeyCmd
  , runConvertCardanoAddressSigningKeyCmd
  , runConvertITNBip32ToStakeKeyCmd
  , runConvertITNExtendedToStakeKeyCmd
  , runConvertITNStakeKeyCmd
  , runConvertToNonExtendedKeyCmd
  , runGetVerificationKeyCmd

    -- * Exports for testing
  , decodeBech32
  ) where

import           Cardano.Api
import qualified Cardano.Api.Byron as ByronApi
import           Cardano.Api.Crypto.Ed25519Bip32 (xPrvFromBytes)
import           Cardano.Api.Shelley

import qualified Cardano.CLI.Byron.Key as Byron
import           Cardano.CLI.Types.Common
import           Cardano.CLI.Types.Errors.CardanoAddressSigningKeyConversionError
import           Cardano.CLI.Types.Errors.ItnKeyConversionError
import           Cardano.CLI.Types.Errors.ShelleyKeyCmdError
import           Cardano.CLI.Types.Key
import qualified Cardano.Crypto.DSIGN as DSIGN
import qualified Cardano.Crypto.Signing as Byron
import qualified Cardano.Crypto.Signing as Byron.Crypto
import qualified Cardano.Crypto.Signing as Crypto
import qualified Cardano.Crypto.Wallet as Crypto
import qualified Cardano.Ledger.Keys as Shelley

import qualified Codec.Binary.Bech32 as Bech32
import qualified Control.Exception as Exception
import           Control.Monad.IO.Class (MonadIO (..))
import           Control.Monad.Trans.Except (ExceptT)
import           Control.Monad.Trans.Except.Extra (firstExceptT, hoistEither, left, newExceptT)
import           Data.Bifunctor (Bifunctor (..))
import           Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import           System.Exit (exitFailure)

runGetVerificationKeyCmd :: SigningKeyFile In
                      -> VerificationKeyFile Out
                      -> ExceptT ShelleyKeyCmdError IO ()
runGetVerificationKeyCmd skf vkf = do
    ssk <- firstExceptT ShelleyKeyCmdReadKeyFileError $
             readSigningKeyFile skf
    withSomeSigningKey ssk $ \sk ->
      let vk = getVerificationKey sk in
      firstExceptT ShelleyKeyCmdWriteFileError . newExceptT $
        writeLazyByteStringFile vkf $ textEnvelopeToJSON Nothing vk


data SomeSigningKey
  = AByronSigningKey           (SigningKey ByronKey)
  | APaymentSigningKey         (SigningKey PaymentKey)
  | APaymentExtendedSigningKey (SigningKey PaymentExtendedKey)
  | AStakeSigningKey           (SigningKey StakeKey)
  | AStakeExtendedSigningKey   (SigningKey StakeExtendedKey)
  | AStakePoolSigningKey       (SigningKey StakePoolKey)
  | AGenesisSigningKey         (SigningKey GenesisKey)
  | AGenesisExtendedSigningKey (SigningKey GenesisExtendedKey)
  | AGenesisDelegateSigningKey (SigningKey GenesisDelegateKey)
  | AGenesisDelegateExtendedSigningKey
                               (SigningKey GenesisDelegateExtendedKey)
  | AGenesisUTxOSigningKey     (SigningKey GenesisUTxOKey)
  | AVrfSigningKey             (SigningKey VrfKey)
  | AKesSigningKey             (SigningKey KesKey)

withSomeSigningKey :: SomeSigningKey
                   -> (forall keyrole. (Key keyrole, HasTypeProxy keyrole) => SigningKey keyrole -> a)
                   -> a
withSomeSigningKey ssk f =
    case ssk of
      AByronSigningKey           sk -> f sk
      APaymentSigningKey         sk -> f sk
      APaymentExtendedSigningKey sk -> f sk
      AStakeSigningKey           sk -> f sk
      AStakeExtendedSigningKey   sk -> f sk
      AStakePoolSigningKey       sk -> f sk
      AGenesisSigningKey         sk -> f sk
      AGenesisExtendedSigningKey sk -> f sk
      AGenesisDelegateSigningKey sk -> f sk
      AGenesisDelegateExtendedSigningKey
                                 sk -> f sk
      AGenesisUTxOSigningKey     sk -> f sk
      AVrfSigningKey             sk -> f sk
      AKesSigningKey             sk -> f sk

readSigningKeyFile
  :: SigningKeyFile In
  -> ExceptT (FileError InputDecodeError) IO SomeSigningKey
readSigningKeyFile skFile =
    newExceptT $
      readKeyFileAnyOf bech32FileTypes textEnvFileTypes skFile
  where
    textEnvFileTypes =
      [ FromSomeType (AsSigningKey AsByronKey)
                      AByronSigningKey
      , FromSomeType (AsSigningKey AsPaymentKey)
                      APaymentSigningKey
      , FromSomeType (AsSigningKey AsPaymentExtendedKey)
                      APaymentExtendedSigningKey
      , FromSomeType (AsSigningKey AsStakeKey)
                      AStakeSigningKey
      , FromSomeType (AsSigningKey AsStakeExtendedKey)
                      AStakeExtendedSigningKey
      , FromSomeType (AsSigningKey AsStakePoolKey)
                      AStakePoolSigningKey
      , FromSomeType (AsSigningKey AsGenesisKey)
                      AGenesisSigningKey
      , FromSomeType (AsSigningKey AsGenesisExtendedKey)
                      AGenesisExtendedSigningKey
      , FromSomeType (AsSigningKey AsGenesisDelegateKey)
                      AGenesisDelegateSigningKey
      , FromSomeType (AsSigningKey AsGenesisDelegateExtendedKey)
                      AGenesisDelegateExtendedSigningKey
      , FromSomeType (AsSigningKey AsGenesisUTxOKey)
                      AGenesisUTxOSigningKey
      , FromSomeType (AsSigningKey AsVrfKey)
                      AVrfSigningKey
      , FromSomeType (AsSigningKey AsKesKey)
                      AKesSigningKey
      ]

    bech32FileTypes =
      [ FromSomeType (AsSigningKey AsPaymentKey)
                      APaymentSigningKey
      , FromSomeType (AsSigningKey AsPaymentExtendedKey)
                      APaymentExtendedSigningKey
      , FromSomeType (AsSigningKey AsStakeKey)
                      AStakeSigningKey
      , FromSomeType (AsSigningKey AsStakeExtendedKey)
                      AStakeExtendedSigningKey
      , FromSomeType (AsSigningKey AsStakePoolKey)
                      AStakePoolSigningKey
      , FromSomeType (AsSigningKey AsVrfKey)
                      AVrfSigningKey
      , FromSomeType (AsSigningKey AsKesKey)
                      AKesSigningKey
      ]


runConvertToNonExtendedKeyCmd
  :: VerificationKeyFile In
  -> VerificationKeyFile Out
  -> ExceptT ShelleyKeyCmdError IO ()
runConvertToNonExtendedKeyCmd evkf vkf =
  writeVerificationKey =<< readExtendedVerificationKeyFile evkf
 where
  -- TODO: Expose a function specifically for this purpose
  -- and explain the extended verification keys can be converted
  -- to their non-extended counterparts however this is NOT the case
  -- for extended signing keys

  writeVerificationKey
    :: SomeAddressVerificationKey
    -> ExceptT ShelleyKeyCmdError IO ()
  writeVerificationKey ssk =
    case ssk of
      APaymentExtendedVerificationKey vk ->
        writeToDisk vkf (castVerificationKey vk :: VerificationKey PaymentKey)
      AStakeExtendedVerificationKey vk ->
        writeToDisk vkf (castVerificationKey vk :: VerificationKey StakeKey)
      AGenesisExtendedVerificationKey vk ->
        writeToDisk vkf (castVerificationKey vk :: VerificationKey GenesisKey)
      AGenesisDelegateExtendedVerificationKey vk ->
        writeToDisk vkf (castVerificationKey vk :: VerificationKey GenesisDelegateKey)
      nonExtendedKey -> left $ ShelleyKeyCmdExpectedExtendedVerificationKey nonExtendedKey


  writeToDisk
   :: Key keyrole
   => File content Out
   -> VerificationKey keyrole
   -> ExceptT ShelleyKeyCmdError IO ()
  writeToDisk vkf' vk =
    firstExceptT ShelleyKeyCmdWriteFileError . newExceptT
      $ writeLazyByteStringFile vkf' $ textEnvelopeToJSON Nothing vk


readExtendedVerificationKeyFile
  :: VerificationKeyFile In
  -> ExceptT ShelleyKeyCmdError IO SomeAddressVerificationKey
readExtendedVerificationKeyFile evkfile = do
  vKey <- firstExceptT ShelleyKeyCmdVerificationKeyReadError
            . newExceptT $ readVerificationKeyTextOrFileAnyOf
                         $ VktofVerificationKeyFile evkfile
  case vKey of
      k@APaymentExtendedVerificationKey{} -> return k
      k@AStakeExtendedVerificationKey{} -> return k
      k@AGenesisExtendedVerificationKey{} -> return k
      k@AGenesisDelegateExtendedVerificationKey{} -> return k
      nonExtendedKey ->
        left $ ShelleyKeyCmdExpectedExtendedVerificationKey nonExtendedKey


runConvertByronKeyCmd
  :: Maybe Text      -- ^ Password (if applicable)
  -> ByronKeyType
  -> SomeKeyFile In  -- ^ Input file: old format
  -> File () Out     -- ^ Output file: new format
  -> ExceptT ShelleyKeyCmdError IO ()
runConvertByronKeyCmd mPwd (ByronPaymentKey format) (ASigningKeyFile skeyPathOld) =
    convertByronSigningKey mPwd format convert skeyPathOld
  where
    convert :: Byron.SigningKey -> SigningKey ByronKey
    convert = ByronSigningKey

runConvertByronKeyCmd mPwd (ByronGenesisKey format) (ASigningKeyFile skeyPathOld) =
    convertByronSigningKey mPwd format convert skeyPathOld
  where
    convert :: Byron.SigningKey -> SigningKey GenesisExtendedKey
    convert (Byron.SigningKey xsk) = GenesisExtendedSigningKey xsk

runConvertByronKeyCmd mPwd (ByronDelegateKey format) (ASigningKeyFile skeyPathOld) =
    convertByronSigningKey mPwd format convert skeyPathOld
  where
    convert :: Byron.SigningKey -> SigningKey GenesisDelegateExtendedKey
    convert (Byron.SigningKey xsk) = GenesisDelegateExtendedSigningKey xsk

runConvertByronKeyCmd _ (ByronPaymentKey NonLegacyByronKeyFormat)
                     (AVerificationKeyFile vkeyPathOld) =
    convertByronVerificationKey convert vkeyPathOld
  where
    convert :: Byron.VerificationKey -> VerificationKey ByronKey
    convert = ByronVerificationKey

runConvertByronKeyCmd _ (ByronGenesisKey NonLegacyByronKeyFormat)
                     (AVerificationKeyFile vkeyPathOld) =
    convertByronVerificationKey convert vkeyPathOld
  where
    convert :: Byron.VerificationKey -> VerificationKey GenesisExtendedKey
    convert (Byron.VerificationKey xvk) = GenesisExtendedVerificationKey xvk

runConvertByronKeyCmd _ (ByronDelegateKey NonLegacyByronKeyFormat)
                     (AVerificationKeyFile vkeyPathOld) =
    convertByronVerificationKey convert vkeyPathOld
  where
    convert :: Byron.VerificationKey
            -> VerificationKey GenesisDelegateExtendedKey
    convert (Byron.VerificationKey xvk) =
      GenesisDelegateExtendedVerificationKey xvk

runConvertByronKeyCmd _ (ByronPaymentKey  LegacyByronKeyFormat)
                      AVerificationKeyFile{} =
    const legacyVerificationKeysNotSupported

runConvertByronKeyCmd _ (ByronGenesisKey  LegacyByronKeyFormat)
                      AVerificationKeyFile{} =
    const legacyVerificationKeysNotSupported

runConvertByronKeyCmd _ (ByronDelegateKey LegacyByronKeyFormat)
                      AVerificationKeyFile{} =
    const legacyVerificationKeysNotSupported

legacyVerificationKeysNotSupported :: ExceptT e IO a
legacyVerificationKeysNotSupported =
    liftIO $ do
      putStrLn $ "convert keys: byron legacy format not supported for "
              ++ "verification keys. Convert the signing key and then get the "
              ++ "verification key."
      exitFailure


convertByronSigningKey
  :: forall keyrole.
     Key keyrole
  => Maybe Text          -- ^ Password (if applicable)
  -> ByronKeyFormat
  -> (Byron.SigningKey -> SigningKey keyrole)
  -> SigningKeyFile In   -- ^ Input file: old format
  -> File () Out         -- ^ Output file: new format
  -> ExceptT ShelleyKeyCmdError IO ()
convertByronSigningKey mPwd byronFormat convert skeyPathOld skeyPathNew = do
    sKey <- firstExceptT ShelleyKeyCmdByronKeyFailure
              $ Byron.readByronSigningKey byronFormat skeyPathOld

    -- Account for password protected legacy Byron keys
    unprotectedSk <- case sKey of
                       ByronApi.AByronSigningKeyLegacy (ByronSigningKeyLegacy sk@(Crypto.SigningKey xprv)) ->
                         case mPwd of
                           -- Change password to empty string
                           Just pwd -> return . Crypto.SigningKey
                                         $ Crypto.xPrvChangePass (Text.encodeUtf8 pwd) (Text.encodeUtf8 "") xprv
                           Nothing -> return sk
                       ByronApi.AByronSigningKey (ByronSigningKey sk) -> return sk


    let sk' :: SigningKey keyrole
        sk' = convert unprotectedSk

    firstExceptT ShelleyKeyCmdWriteFileError . newExceptT $
      writeLazyByteStringFile skeyPathNew $ textEnvelopeToJSON Nothing sk'

convertByronVerificationKey
  :: forall keyrole.
     Key keyrole
  => (Byron.VerificationKey -> VerificationKey keyrole)
  -> VerificationKeyFile In -- ^ Input file: old format
  -> File () Out            -- ^ Output file: new format
  -> ExceptT ShelleyKeyCmdError IO ()
convertByronVerificationKey convert vkeyPathOld vkeyPathNew = do

    vk <- firstExceptT ShelleyKeyCmdByronKeyFailure $
            Byron.readPaymentVerificationKey vkeyPathOld

    let vk' :: VerificationKey keyrole
        vk' = convert vk

    firstExceptT ShelleyKeyCmdWriteFileError . newExceptT $
      writeLazyByteStringFile vkeyPathNew $ textEnvelopeToJSON Nothing vk'


runConvertByronGenesisVerificationKeyCmd
  :: VerificationKeyBase64  -- ^ Input key raw old format
  -> File () Out            -- ^ Output file: new format
  -> ExceptT ShelleyKeyCmdError IO ()
runConvertByronGenesisVerificationKeyCmd (VerificationKeyBase64 b64ByronVKey) vkeyPathNew = do

    vk <- firstExceptT (ShelleyKeyCmdByronKeyParseError . textShow)
        . hoistEither
        . Byron.Crypto.parseFullVerificationKey
        . Text.pack
        $ b64ByronVKey

    let vk' :: VerificationKey GenesisKey
        vk' = convert vk

    firstExceptT ShelleyKeyCmdWriteFileError . newExceptT $
      writeLazyByteStringFile vkeyPathNew $ textEnvelopeToJSON Nothing vk'
  where
    convert :: Byron.VerificationKey -> VerificationKey GenesisKey
    convert (Byron.VerificationKey xvk) =
      castVerificationKey (GenesisExtendedVerificationKey xvk)


--------------------------------------------------------------------------------
-- ITN verification/signing key conversion to Haskell verficiation/signing keys
--------------------------------------------------------------------------------

runConvertITNStakeKeyCmd
  :: SomeKeyFile In
  -> File () Out
  -> ExceptT ShelleyKeyCmdError IO ()
runConvertITNStakeKeyCmd (AVerificationKeyFile (File vk)) outFile = do
  bech32publicKey <- firstExceptT ShelleyKeyCmdItnKeyConvError . newExceptT $
                     readFileITNKey vk
  vkey <- hoistEither
    . first ShelleyKeyCmdItnKeyConvError
    $ convertITNVerificationKey bech32publicKey
  firstExceptT ShelleyKeyCmdWriteFileError . newExceptT $
    writeLazyByteStringFile outFile $ textEnvelopeToJSON Nothing vkey

runConvertITNStakeKeyCmd (ASigningKeyFile (File sk)) outFile = do
  bech32privateKey <- firstExceptT ShelleyKeyCmdItnKeyConvError . newExceptT $
                      readFileITNKey sk
  skey <- hoistEither
    . first ShelleyKeyCmdItnKeyConvError
    $ convertITNSigningKey bech32privateKey
  firstExceptT ShelleyKeyCmdWriteFileError . newExceptT
    $ writeLazyByteStringFile outFile
    $ textEnvelopeToJSON Nothing skey

runConvertITNExtendedToStakeKeyCmd :: SomeKeyFile In -> File () Out -> ExceptT ShelleyKeyCmdError IO ()
runConvertITNExtendedToStakeKeyCmd (AVerificationKeyFile _) _ = left ShelleyKeyCmdWrongKeyTypeError
runConvertITNExtendedToStakeKeyCmd (ASigningKeyFile (File sk)) outFile = do
  bech32privateKey <- firstExceptT ShelleyKeyCmdItnKeyConvError . newExceptT $ readFileITNKey sk
  skey <- hoistEither . first ShelleyKeyCmdItnKeyConvError
            $ convertITNExtendedSigningKey bech32privateKey
  firstExceptT ShelleyKeyCmdWriteFileError . newExceptT
    $ writeLazyByteStringFile outFile
    $ textEnvelopeToJSON Nothing skey

runConvertITNBip32ToStakeKeyCmd :: SomeKeyFile In -> File () Out -> ExceptT ShelleyKeyCmdError IO ()
runConvertITNBip32ToStakeKeyCmd (AVerificationKeyFile _) _ = left ShelleyKeyCmdWrongKeyTypeError
runConvertITNBip32ToStakeKeyCmd (ASigningKeyFile (File sk)) outFile = do
  bech32privateKey <- firstExceptT ShelleyKeyCmdItnKeyConvError . newExceptT $ readFileITNKey sk
  skey <- hoistEither . first ShelleyKeyCmdItnKeyConvError
            $ convertITNBIP32SigningKey bech32privateKey
  firstExceptT ShelleyKeyCmdWriteFileError . newExceptT
    $ writeLazyByteStringFile outFile
    $ textEnvelopeToJSON Nothing skey

-- | Convert public ed25519 key to a Shelley stake verification key
convertITNVerificationKey :: Text -> Either ItnKeyConversionError (VerificationKey StakeKey)
convertITNVerificationKey pubKey = do
  (_, _, keyBS) <- first ItnKeyBech32DecodeError (decodeBech32 pubKey)
  case DSIGN.rawDeserialiseVerKeyDSIGN keyBS of
    Just verKey -> Right . StakeVerificationKey $ Shelley.VKey verKey
    Nothing -> Left $ ItnVerificationKeyDeserialisationError keyBS

-- | Convert private ed22519 key to a Shelley signing key.
convertITNSigningKey :: Text -> Either ItnKeyConversionError (SigningKey StakeKey)
convertITNSigningKey privKey = do
  (_, _, keyBS) <- first ItnKeyBech32DecodeError (decodeBech32 privKey)
  case DSIGN.rawDeserialiseSignKeyDSIGN keyBS of
    Just signKey -> Right $ StakeSigningKey signKey
    Nothing -> Left $ ItnSigningKeyDeserialisationError keyBS

-- | Convert extended private ed22519 key to a Shelley signing key
-- Extended private key = 64 bytes,
-- Public key = 32 bytes.
convertITNExtendedSigningKey :: Text -> Either ItnKeyConversionError (SigningKey StakeExtendedKey)
convertITNExtendedSigningKey privKey = do
  (_, _, privkeyBS) <- first ItnKeyBech32DecodeError (decodeBech32 privKey)
  let dummyChainCode = BS.replicate 32 0
  case xPrvFromBytes $ BS.concat [privkeyBS, dummyChainCode] of
    Just xprv -> Right $ StakeExtendedSigningKey xprv
    Nothing -> Left $ ItnSigningKeyDeserialisationError privkeyBS

-- BIP32 Private key = 96 bytes (64 bytes extended private key + 32 bytes chaincode)
-- BIP32 Public Key = 64 Bytes
convertITNBIP32SigningKey :: Text -> Either ItnKeyConversionError (SigningKey StakeExtendedKey)
convertITNBIP32SigningKey privKey = do
  (_, _, privkeyBS) <- first ItnKeyBech32DecodeError (decodeBech32 privKey)
  case xPrvFromBytes privkeyBS of
    Just xprv -> Right $ StakeExtendedSigningKey xprv
    Nothing -> Left $ ItnSigningKeyDeserialisationError privkeyBS

readFileITNKey :: FilePath -> IO (Either ItnKeyConversionError Text)
readFileITNKey fp = do
  eStr <- Exception.try $ readFile fp
  case eStr of
    Left e -> return . Left $ ItnReadBech32FileError fp e
    Right str -> return . Right . Text.concat $ Text.words $ Text.pack str

--------------------------------------------------------------------------------
-- `cardano-address` extended signing key conversions
--------------------------------------------------------------------------------

runConvertCardanoAddressSigningKeyCmd
  :: CardanoAddressKeyType
  -> SigningKeyFile In
  -> File () Out
  -> ExceptT ShelleyKeyCmdError IO ()
runConvertCardanoAddressSigningKeyCmd keyType skFile outFile = do
  sKey <- firstExceptT ShelleyKeyCmdCardanoAddressSigningKeyFileError
    . newExceptT
    $ readSomeCardanoAddressSigningKeyFile keyType skFile
  firstExceptT ShelleyKeyCmdWriteFileError . newExceptT
    $ writeSomeCardanoAddressSigningKeyFile outFile sKey

-- | Some kind of signing key that was converted from a @cardano-address@
-- signing key.
data SomeCardanoAddressSigningKey
  = ACardanoAddrShelleyPaymentSigningKey !(SigningKey PaymentExtendedKey)
  | ACardanoAddrShelleyStakeSigningKey !(SigningKey StakeExtendedKey)
  | ACardanoAddrByronSigningKey !(SigningKey ByronKey)

-- | Decode a Bech32-encoded string.
decodeBech32
  :: Text
  -> Either Bech32DecodeError (Bech32.HumanReadablePart, Bech32.DataPart, ByteString)
decodeBech32 bech32Str =
  case Bech32.decodeLenient bech32Str of
    Left err -> Left (Bech32DecodingError err)
    Right (hrPart, dataPart) ->
      case Bech32.dataPartToBytes dataPart of
        Nothing ->
          Left $ Bech32DataPartToBytesError (Bech32.dataPartToText dataPart)
        Just bs -> Right (hrPart, dataPart, bs)

-- | Convert a Ed25519 BIP32 extended signing key (96 bytes) to a @cardano-crypto@
-- style extended signing key.
--
-- Note that both the ITN and @cardano-address@ use this key format.
convertBip32SigningKey
  :: ByteString
  -> Either CardanoAddressSigningKeyConversionError Crypto.XPrv
convertBip32SigningKey signingKeyBs =
  case xPrvFromBytes signingKeyBs of
    Just xPrv -> Right xPrv
    Nothing ->
      Left $ CardanoAddressSigningKeyDeserialisationError signingKeyBs

-- | Read a file containing a Bech32-encoded Ed25519 BIP32 extended signing
-- key.
readBech32Bip32SigningKeyFile
  :: SigningKeyFile In
  -> IO (Either (FileError CardanoAddressSigningKeyConversionError) Crypto.XPrv)
readBech32Bip32SigningKeyFile (File fp) = do
  eStr <- Exception.try $ readFile fp
  case eStr of
    Left e -> pure . Left $ FileIOError fp e
    Right str ->
      case decodeBech32 (Text.concat $ Text.words $ Text.pack str) of
        Left err ->
          pure $ Left $
            FileError fp (CardanoAddressSigningKeyBech32DecodeError err)
        Right (_hrPart, _dataPart, bs) ->
          pure $ first (FileError fp) (convertBip32SigningKey bs)

-- | Read a file containing a Bech32-encoded @cardano-address@ extended
-- signing key.
readSomeCardanoAddressSigningKeyFile
  :: CardanoAddressKeyType
  -> SigningKeyFile In
  -> IO (Either (FileError CardanoAddressSigningKeyConversionError) SomeCardanoAddressSigningKey)
readSomeCardanoAddressSigningKeyFile keyType skFile = do
    xPrv <- readBech32Bip32SigningKeyFile skFile
    pure (toSomeCardanoAddressSigningKey <$> xPrv)
  where
    toSomeCardanoAddressSigningKey :: Crypto.XPrv -> SomeCardanoAddressSigningKey
    toSomeCardanoAddressSigningKey xPrv =
      case keyType of
        CardanoAddressShelleyPaymentKey ->
          ACardanoAddrShelleyPaymentSigningKey
            (PaymentExtendedSigningKey xPrv)
        CardanoAddressShelleyStakeKey ->
          ACardanoAddrShelleyStakeSigningKey (StakeExtendedSigningKey xPrv)
        CardanoAddressIcarusPaymentKey ->
          ACardanoAddrByronSigningKey $
            ByronSigningKey (Byron.SigningKey xPrv)
        CardanoAddressByronPaymentKey ->
          ACardanoAddrByronSigningKey $
            ByronSigningKey (Byron.SigningKey xPrv)

-- | Write a text envelope formatted file containing a @cardano-address@
-- extended signing key, but converted to a format supported by @cardano-cli@.
writeSomeCardanoAddressSigningKeyFile
  :: File direction Out
  -> SomeCardanoAddressSigningKey
  -> IO (Either (FileError ()) ())
writeSomeCardanoAddressSigningKeyFile outFile skey =
  case skey of
    ACardanoAddrShelleyPaymentSigningKey sk ->
      writeLazyByteStringFile outFile $ textEnvelopeToJSON Nothing sk
    ACardanoAddrShelleyStakeSigningKey sk ->
      writeLazyByteStringFile outFile $ textEnvelopeToJSON Nothing sk
    ACardanoAddrByronSigningKey sk ->
      writeLazyByteStringFile outFile $ textEnvelopeToJSON Nothing sk