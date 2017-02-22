import           Control.Arrow             (first)
import           Control.Monad             (when, forever)
import           Control.Monad.Random      (Rand, RandomGen,
                                            getRandom, evalRandIO)
import           Data.Binary               (Binary (..), decodeOrFail, encode,
                                            getWord8, putWord8)
import qualified Data.ByteString           as B
import qualified Data.ByteString.Base64    as B64
import qualified Data.ByteString.Char8     as C
import           Data.ByteString.Lazy      (fromStrict, toStrict)
import qualified Network.Kademlia          as K
import           System.Environment        (getArgs)
import           System.Exit               (exitSuccess)

data Pong = Pong
          deriving (Eq, Show)

instance K.Serialize Pong where
    toBS = toBSBinary
    fromBS = fromBSBinary

type KademliaValue = Pong
newtype KademliaID = KademliaID B.ByteString
                   deriving (Show, Eq, Ord)

type KademliaInstance = K.KademliaInstance KademliaID KademliaValue
instance K.Serialize KademliaID where
    toBS (KademliaID bs)
        | B.length bs >= kIdLength = B.take kIdLength bs
        | otherwise                = error $ "KademliaID to short!"

    fromBS bs
        | B.length bs >= kIdLength = Right . first KademliaID . B.splitAt kIdLength $ bs
        | otherwise                = Left "ByteString too short!"

instance Binary Pong where
    put _ = putWord8 1
    get = do
        w <- getWord8
        if w == 1
        then pure Pong
        else fail "no parse pong"

kIdLength :: Integral a => a
kIdLength = 10

toBSBinary :: Binary b => b -> B.ByteString
toBSBinary = toStrict . encode

fromBSBinary :: Binary b => B.ByteString -> Either String (b, B.ByteString)
fromBSBinary bs =
    case decodeOrFail $ fromStrict bs of
        Left (_, _, errMsg)  -> Left errMsg
        Right (rest, _, res) -> Right (res, toStrict rest)

generateByteString :: (RandomGen g) => Int -> Rand g B.ByteString
generateByteString len = C.pack <$> sequence (replicate len getRandom)

connectToPeer :: KademliaInstance -> K.Peer -> B.ByteString -> IO K.JoinResult
connectToPeer inct peer peerId = do
    let peerNode = K.Node peer . KademliaID $ peerId
    K.joinNetwork inct peerNode

processCommand :: String -> IO Bool
processCommand "exit" = return True
processCommand s = do
    putStrLn $ "Invalid command: " ++ s
    return False

main :: IO ()
main = do
    args <- getArgs
    print args
    let port      = read $ args !! 0
        peerIdRaw = C.pack $ args !! 1
        peerHost  = args !! 2
        peerPort  = read $ args !! 3
    peerId <- either (\e -> do
                         putStrLn $ "ERROR: Invalid base64 key: " ++ e
                         return $ C.pack "0")
                     return
                     (B64.decode peerIdRaw)

    ourId <- evalRandIO (generateByteString kIdLength)

    let logError = putStrLn . ("ERROR: " ++)
    let logInfo = putStrLn . ("INFO: " ++)

    kInstance <- K.createL port (KademliaID ourId) K.defaultConfig logInfo logError
    when (peerPort /= 0) $ do
        putStrLn "Connecting to peer"
        r <- connectToPeer kInstance (K.Peer peerHost peerPort) peerId
        when (r /= K.JoinSuccess) $
            putStrLn . ("Connection to peer failed "++) . show $ r

    forever $ do
        command <- getLine
        result <- processCommand command
        when result $ do
          K.close kInstance
          exitSuccess
