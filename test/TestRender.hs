{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -fno-warn-name-shadowing #-}

module TestRender where

import           Lucid.Page

import           Control.Lens
import           Control.Monad
import           Data.Default
import           Data.Monoid
import           Data.Text (Text)
import qualified Data.Text.Lazy as Lazy
import qualified Data.Text.Lazy.IO as Text
import           Test.Tasty.Hspec
import Network.HTTP.Client
import Pipes
import Pipes.HTTP
import qualified Pipes.ByteString as PB  -- from `pipes-bytestring`

page1 :: Page
page1 =
  pageHtmlBody .~ TestRender.button  $
  pageCss      .~ css $
  pageJsGlobal .~ mempty $
  pageJsOnLoad .~ click $
  pageLibsCss  .~ cssLibs $
  pageLibsJs   .~ jsLibs $
  mempty

page2 :: Page
page2 =      
  pageLibsCss .~ cssLibsLocal $
  pageLibsJs .~ jsLibsLocal $
  page1

pagecfg2 :: PageConfig
pagecfg2 = 
  pagecConcerns .~ Separated $ 
  pagecRender .~ Pretty $ 
  pagecStructure .~ Headless $ 
  pagecLibs .~ LocalLibs "../static/" $ 
  def

cssLibs :: [Text]
cssLibs = 
  ["http://maxcdn.bootstrapcdn.com/font-awesome/4.3.0/css/font-awesome.min.css"]

cssLibsLocal :: [Text]
cssLibsLocal = 
  ["css/font-awesome.min.css"]

jsLibs :: [Text]
jsLibs = 
  [ "http://code.jquery.com/jquery-1.6.3.min.js"
  ]

jsLibsLocal :: [Text]
jsLibsLocal = 
  [ "jquery-2.1.3.min.js"
  ]

css :: Css
css = do
  fontSize (px 10)
  fontFamily ["Arial", "Helvetica"] [sansSerif]
  "#btnGo" ? do
      marginTop (px 20)
      marginBottom (px 20)
  "#btnGo.on" ?
      color green

-- js
click :: JStat
click =
  [jmacro|
   $("#btnGo").click( function() {
     $("#btnGo").toggleClass("on");
     alert("bada bing!");
   });
  |]

button :: Html ()
button = with button_ [id_ "btnGo", type_ "button"] ("Go " <> with i_ [class_ "fa fa-play"] mempty)

generatePage :: FilePath -> FilePath -> PageConfig -> Page -> IO ()
generatePage dir stem pc p = 
  renderPageToFile dir (pagecFilenames .~ concernNames "" stem $ pc) p

generatePages :: Traversable t => FilePath -> t (FilePath, PageConfig, Page) -> IO ()
generatePages dir xs = void $ sequenceA $ (\(fp,pc,p) -> generatePage dir fp pc p) <$> xs

genTest :: FilePath -> IO ()
genTest dir = void $ generatePages dir 
  [ ("default", def, page1)
  , ("sep", pagecfg2, page2)
  ]

testVsFile :: FilePath -> FilePath -> PageConfig -> Page -> IO Bool
testVsFile dir stem pc p = do
  let names = concernNames "" stem
  let pc' = pagecFilenames .~ names $ pc 
  let t = renderPageText pc' p
  case pc^.pagecConcerns of
    Inline -> do
      t' <- Text.readFile (dir <> _html names)
      return $ _html t == t'
    Separated -> do
      t' <- sequenceA $ Text.readFile <$> (dir<>) <$> names
      return $ t == t'

textVsFile :: FilePath -> FilePath -> PageConfig -> Page -> IO (Concerns Lazy.Text, Concerns Lazy.Text)
textVsFile dir stem pc p = do
  let names = concernNames "" stem
  let pc' = pagecFilenames .~ names $ pc 
  let t = renderPageText pc' p
  case pc^.pagecConcerns of
    Inline -> do
      t' <- Text.readFile (dir <> _html names)
      return (t, Concerns mempty mempty t')
    Separated -> do
      t' <- sequenceA $ Text.readFile <$> (dir<>) <$> names
      return (t, t')

testsRender :: IO (SpecWith())
testsRender = do
  let dir = "test/canned/"
  return $ describe "Lucid.Page.Render" $ do
    it "run genTest 'test/canned/' to refresh canned files." True
    it "renderPage mempty" $ renderText (renderPage mempty) `shouldBe` "<html><head><meta charset=\"utf-8\"><script>window.onload=(function(){})</script><body></body></head></html>"
    it "renderPageToFile, renderPage (compared with default canned file)" $
      testVsFile dir "default" def page1 `shouldReturn` True
    it "the various PageConfig's" $
      testVsFile dir "sep" pagecfg2 page2 `shouldReturn` True

-- testServe :: PageConfig -> Page -> IO ()
testServe pc p = serve' (servePageWith pc p)

pServe :: Page
pServe =
  pageLibsCss .~ cssLibsLocal $
  pageLibsJs .~ jsLibsLocal $
  page1

pcServe :: PageConfig
pcServe = 
  pagecConcerns .~ Separated $ 
  pagecRender .~ Pretty $ 
  pagecStructure .~ Headless $ 
  pagecLibs .~ LocalLibs "static/" $ 
  pagecFilenames .~ 
    Concerns "static/page-serve.css" "static/page-serve.js" mempty $ 
  def

testRequest = def { Pipes.HTTP.method = "GET", Pipes.HTTP.port = 8001 }

testClient = withManager defaultManagerSettings

testResponse manager = withResponse testRequest manager

client = do
    withManager tlsManagerSettings $ \m ->
        withHTTP testRequest m $ \resp ->
            Pipes.runEffect $ responseBody resp >-> PB.stdout




tReq :: IO Pipes.HTTP.Request
tReq = parseUrl "0.0.0.0:8001"
