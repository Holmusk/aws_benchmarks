#!/usr/bin/env stack
--runghc
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE NoImplicitPrelude   #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# OPTIONS_GHC -Wall            #-}

import Control.Concurrent
import Control.Concurrent.Async
import Control.Concurrent.QSem
import Control.Exception
import Control.Lens hiding ((.=))
import Control.Monad.Trans.AWS
import Data.Aeson hiding (Error)
import Data.Aeson.Lens
import Data.ByteString (pack)
import Data.Traversable
import Data.UUID.Types (UUID)
import Database.PostgreSQL.Simple
import Network.AWS.Data
import Network.AWS.S3
import Network.AWS.SQS
import Relude
import System.Random

import qualified Data.UUID.Types as UUID (toText)


config :: Config
config = Config {
    uploadConcurrency = 10, -- How many files to upload at a time
    sqsConcurrency = 30, -- how many threads will poll SQS at a time
    fileSize = 0, -- in bytes
    totalFiles = 1000
}

main :: IO ()
main = do
    resetDb

    fileContent <- randomByteString (fileSize config)
    fileNames :: [UUID] <- replicateM (totalFiles config) randomIO

    lgr <- newLogger Error stdout
    env <- newEnv Discover <&> (envLogger .~ lgr) . (envRegion .~ Singapore)
    queueUrl <- (^. gqursQueueURL) <$> (runResourceT . runAWST env $ (send (getQueueURL "benchmark-test-upload-queue")))

    uploadThread <- async $ traverseThrottled (uploadConcurrency config) (handleFile env fileContent) fileNames
    sqsThreads <- sequence $ async <$> replicate (sqsConcurrency config) (listenOnSQS env queueUrl)
    wait uploadThread
    waitForAllSQSEvents sqsThreads
    print "All SQS events are in, now run `make stats`"

resetDb :: IO ()
resetDb = do
    conn <- connectPostgreSQL dbConnString
    void $ execute_ conn "DROP TABLE IF EXISTS bench"
    void $ execute_ conn "CREATE TABLE bench ( file_name TEXT PRIMARY KEY, upload TIMESTAMPTZ NOT NULL, message TIMESTAMPTZ, time_taken INT)"
    close conn

handleFile :: Env -> ByteString -> UUID -> IO ()
handleFile env fileContent fileName = do
    -- Exluding a pool here because localhost connections are so cheap
    conn <- connectPostgreSQL dbConnString
    runResourceT . runAWST env $ send (putObject (BucketName "benchmark-test-upload-bucket") (ObjectKey $ UUID.toText fileName) (toBody fileContent))
    execute conn "INSERT INTO bench VALUES (?, NOW(), NULL)" [fileName]
    close conn

listenOnSQS :: Env -> Text -> IO ()
listenOnSQS env url = do
    conn <- connectPostgreSQL dbConnString
    messages <- runResourceT . runAWST env $ send $ receiveMessage url & rmMaxNumberOfMessages .~ (Just 10)
    forM_ (messages ^. rmrsMessages) $ \message -> do
        let Just receiptHandle = message ^. mReceiptHandle
        let fileName = extactFileName $ message ^. mBody
        void $ execute conn "UPDATE bench SET message = NOW() WHERE file_name = ?" [fileName]
        runResourceT . runAWST env $ send (deleteMessage url receiptHandle)
    close conn
    listenOnSQS env url

waitForAllSQSEvents :: [Async a] -> IO ()
waitForAllSQSEvents sqsHandlers = do
    conn <- connectPostgreSQL dbConnString
    rows :: [Only Int] <- query_ conn "SELECT 1 FROM bench WHERE message IS NULL"
    close conn
    if null rows
    then void $ sequence $ cancel <$> sqsHandlers
    else threadDelay 1000000 >> waitForAllSQSEvents sqsHandlers

data Config = Config {
    uploadConcurrency :: !Int,
    sqsConcurrency    :: !Int,
    fileSize          :: !Int,
    totalFiles        :: !Int
}

dbConnString :: ByteString
dbConnString = "host='localhost' port=5432 dbname='bench' user='test' password='test'"

randomByteString :: Int -> IO ByteString
randomByteString len = do
    bytes <- replicateM len randomIO
    return $ pack bytes

-- https://stackoverflow.com/questions/29155068/running-parallel-url-downloads-with-a-worker-pool-in-haskell
traverseThrottled :: Traversable t => Int -> (a -> IO b) -> t a -> IO (t b)
traverseThrottled concLevel action taskContainer = do
    sem <- newQSem concLevel
    let throttledAction = bracket_ (waitQSem sem) (signalQSem sem) . action
    runConcurrently (traverse (Concurrently . throttledAction) taskContainer)

extactFileName :: Maybe Text -> Text
extactFileName Nothing = ""
extactFileName (Just json) =
    let Just keyName = json
                        ^? key "Records"
                        . nth 0
                        . key "s3"
                        . key "object"
                        . key "key"
                        . _String
    in keyName
