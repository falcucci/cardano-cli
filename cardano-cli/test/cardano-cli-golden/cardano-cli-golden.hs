import qualified Cardano.Crypto.Init as Crypto

import           System.IO (BufferMode (LineBuffering), hSetBuffering, hSetEncoding, stdout, utf8)

import           Hedgehog.Main (defaultMain)
import qualified Test.Golden.Byron.SigningKeys
import qualified Test.Golden.Byron.Tx
import qualified Test.Golden.Byron.UpdateProposal
import qualified Test.Golden.Byron.Vote
import qualified Test.Golden.ErrorsSpec
import qualified Test.Golden.Help
import qualified Test.Golden.Key
import qualified Test.Golden.Shelley
import qualified Test.Golden.TxView

main :: IO ()
main = do
  Crypto.cryptoInit

  hSetBuffering stdout LineBuffering
  hSetEncoding stdout utf8
  defaultMain
    [ Test.Golden.Byron.SigningKeys.tests
    , Test.Golden.Byron.Tx.txTests
    , Test.Golden.Byron.UpdateProposal.updateProposalTest
    , Test.Golden.Byron.Vote.voteTests
    , Test.Golden.ErrorsSpec.messagesTests
    , Test.Golden.Help.helpTests
    , Test.Golden.Key.keyTests
    , Test.Golden.Shelley.keyTests
    , Test.Golden.Shelley.certificateTests
    , Test.Golden.Shelley.keyConversionTests
    , Test.Golden.Shelley.metadataTests
    , Test.Golden.Shelley.multiSigTests
    , Test.Golden.Shelley.txTests
    , Test.Golden.Shelley.governancePollTests
    , Test.Golden.TxView.txViewTests
    ]
