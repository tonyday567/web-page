{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wall #-}

import Control.Category (id)
import Control.Lens hiding (Wrapped, Unwrapped)
import Data.Attoparsec.Text
import Lucid hiding (b_)
import Network.Wai
import Network.Wai.Middleware.RequestLogger
import Network.Wai.Middleware.Static (addBase, noDots, staticPolicy, (>->))
import Options.Generic
import Protolude hiding (replace, Rep, log)
import Web.Page
import Web.Page.Examples
import Web.Scotty
import qualified Box
import qualified Data.Text as Text

testPage :: Text -> Text -> [(Text, Html ())] -> Page
testPage title mid sections =
  showJs <>
  bootstrapPage <>
  bridgePage &
  #htmlHeader .~ title_ "iroTestPage" &
  #htmlBody .~ b_ "container" (mconcat
    [ b_ "row" (h1_ (toHtml title))
    , b_ "row" (h2_ ("middleware: " <> toHtml mid))
    , b_ "row" $ mconcat $ (\(t,h) -> b_ "col" (h2_ (toHtml t) <> with div_ [id_ t] h)) <$> sections
    ])

-- | bridge testing without the SharedRep method
rangeTest :: Input Int
rangeTest = bridgeify $ bootify $
  Input
  3
  (Slider
  [ style_ "max-width:15rem;"
  , min_ "0"
  , max_ "5"
  , step_ "1"
  ])
  (Just "range example")
  "rangeid"
  []

textTest :: Input Text
textTest = bridgeify $ bootify $
  Input
  "abc"
  TextBox
  (Just "label")
  "textid"
  [ style_ "max-width:15rem;"
  , placeholder_ "test placeholder"
  ]

initBridgeTest :: (Int, Text)
initBridgeTest = (rangeTest ^. #val, textTest ^. #val)

stepBridgeTest :: Element -> (Int, Text) -> Either Text (Int, Text)
stepBridgeTest (Element "rangeid" v) (_, t) =
  either
  (Left . Text.pack)
  (\x -> Right (x,t))
  p
  where
    p = parseOnly decimal v
stepBridgeTest (Element "textid" v) (n, _) = Right (n,v)
stepBridgeTest e _ = Left $ "unknown id: " <> show e

stepBridgeTest' :: Element -> (Int, Text) -> (Int,Text)
stepBridgeTest' e s =
  case stepBridgeTest e s of
    Left _ -> s
    Right x -> x

sendBridgeTest :: (Show a) => Engine -> Either Text a -> IO ()
sendBridgeTest e (Left err) = append e "log" err
sendBridgeTest e (Right a) =
  replace e "output"
  (toText $ cardify [] mempty (Just "output")
    (toHtml  (show a :: Text)))

consumeBridgeTest :: Event Value -> Engine -> IO (Int, Text)
consumeBridgeTest ev e =
  valueConsume initBridgeTest stepBridgeTest'
  ( (Box.liftC <$> Box.showStdout) <>
    pure (Box.Committer (\v -> sendBridgeTest e v >> pure True))
  ) (bridge ev e)

midBridgeTest :: (Show a) => Html () -> (Event Value -> Engine -> IO a) -> Application -> Application
midBridgeTest init eeio = start $ \ ev e -> do
  append e "input" (toText init)
  final <- eeio ev e `finally` putStrLn ("midBridgeTest finalled" :: Text)
  putStrLn $ ("final value was: " :: Text) <> show final

-- * SharedRep testing
midShared ::
  (Show a) =>
  SharedRep IO a ->
  (Engine -> Either Text (HashMap Text Text, Either Text a) -> IO ()) ->
  Application -> Application
midShared sr action = start $ \ ev e ->
  void $ runOnEvent
  sr
  (zoom _2 . initRep e show)
  (action e)
  (bridge ev e)

initRep
  :: Engine
  -> ((HashMap Text Text, Either Text a) -> Text)
  -> Rep a
  -> StateT (HashMap Text Text) IO ()
initRep e rend r =
  void $ oneRep r
  (\(Rep h fa) m -> do
      append e "input" (toText h)
      replace e "output" (rend (fa m)))

results :: (a -> Text) -> Engine -> a -> IO ()
results r e x = replace e "output" (r x)

logResults :: (a -> Text) -> Engine -> Either Text a -> IO ()
logResults _ e (Left err) = append e "log" (err <> "<br>")
logResults r e (Right x) = results r e x

-- | evaluate a Fiddle, without attempting to downstream bridging
midFiddle ::
  Concerns Text ->
  Application -> Application
midFiddle cs = start $ \ ev e ->
  void $ runOnEvent
  (repConcerns cs)
  (zoom _2 . initFiddleRep e show)
  (logFiddle e . second snd)
  (bridge ev e)

initFiddleRep
  :: Engine
  -> ((HashMap Text Text, Either Text a) -> Text)
  -> Rep a
  -> StateT (HashMap Text Text) IO ()
initFiddleRep e _ r =
  void $ oneRep r
  (\(Rep h _) _ ->
      append e "input" (toText h))

logFiddle :: Engine -> Either Text (Either Text (Concerns Text, Bool)) -> IO ()
logFiddle e (Left err) = append e "log" ("map error: " <> err)
logFiddle e (Right (Left err)) = append e "log" ("parse error: " <> err)
logFiddle e (Right (Right (c,u))) = bool (pure ()) (sendConcerns e "output" c) u

-- | evaluate a Fiddle, and any downstream bridging representation
midViaFiddle
  :: Show a
  => SharedRep IO a
  -> Application -> Application
midViaFiddle sr = start $ \ ev e ->
  void $ runOnEvent
  (viaFiddle sr)
  (zoom _2 . initViaFiddleRep e show)
  (logViaFiddle e show . second snd)
  (bridge ev e)

initViaFiddleRep
  :: Engine
  -> (a -> Text)
  -> Rep (Bool, Concerns Text, a)
  -> StateT (HashMap Text Text) IO ()
initViaFiddleRep e rend r =
  void $ oneRep r
  (\(Rep h fa) m -> do
      append e "input" (toText h)
      case (snd $ fa m) of
        Left err -> append e "log" ("map error: " <> err)
        Right (_,c,a) -> do
          sendConcerns e "representation" c
          replace e "output" (rend a))

logViaFiddle :: Engine -> (a -> Text) -> Either Text (Either Text (Bool, Concerns Text, a)) -> IO ()
logViaFiddle e _ (Left err) = append e "log" ("map error: " <> err)
logViaFiddle e _ (Right (Left err)) = append e "log" ("parse error: " <> err)
logViaFiddle e r (Right (Right (True,c,a))) = do
  sendConcerns e "representation" c
  replace e "output" (r a)
logViaFiddle e r (Right (Right (False,_,a))) = replace e "output" (r a)

data MidType = Dev | Prod | Bridge | Listify | Fiddle | ViaFiddle | NoMid deriving (Eq, Read, Show, Generic)

instance ParseField MidType
instance ParseRecord MidType
instance ParseFields MidType

data Opts w = Opts
  { midtype :: w ::: MidType <?> "type of middleware processing"
  , log :: w ::: Maybe Bool <?> "server log to stdout"
  , logPath :: w ::: Maybe Bool <?> "log raw path"
  } deriving (Generic)

instance ParseRecord (Opts Wrapped)

main :: IO ()
main = do
  o :: Opts Unwrapped <- unwrapRecord "examples for web-page"
  let tr = maybe False id
  scotty 3000 $ do
    middleware $ staticPolicy (noDots >-> addBase "other")
    middleware $ staticPolicy (noDots >-> addBase "saves")
    when (tr $ log o) $
      middleware logStdoutDev
    when (tr $ logPath o) $
      middleware $ \app req res ->
        putStrLn ("raw path:" :: Text) >>
        print (rawPathInfo req) >> app req res
  -- Only one middleware servicing the web socket can be run at a time.  Simply switching on based on paths doesn't work because socket comms comes through "/"
  -- so that the first bridge middleware consumes all the elements
    middleware $ case midtype o of
      NoMid -> id
      Prod -> midShared
          (maybeRep (Just "maybe") True repExamples) (logResults show)
      Dev -> midShared
              (datalist (Just "label") ["first", "2", "3"] "2") (logResults show)
      --    (chooseFile "Save Button" "") (logResults show)
      Listify -> midShared (listifyExample 5) (logResults show)
      Bridge -> midBridgeTest (toHtml rangeTest <> toHtml textTest)
           consumeBridgeTest
      Fiddle -> midFiddle fiddleExample
      ViaFiddle -> midViaFiddle
          (slider' Nothing 0 10 0.01 4)
          -- (repSumTypeExample 2 "default text" SumOnly)
    servePageWith "/simple" defaultPageConfig page1
    servePageWith "/iro" defaultPageConfig
      (testPage "iro" (show $ midtype o)
        [ ("input", mempty)
        , ("representation", mempty)
        , ("output", mempty)
        ])
    servePageWith "/" defaultPageConfig
      (testPage "prod" (show $ midtype o)
       [ ("input", mempty)
       , ("output",
          (bool mempty
            (toHtml (show initBridgeTest :: Text))
            (midtype o == Bridge)))
       ])

-- window.open("/", "window.open test title", "menubar=yes,location=yes,resizable=yes,scrollbars=yes,status=yes")
