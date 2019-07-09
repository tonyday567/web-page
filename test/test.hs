{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Lens
import Lucid
import Protolude
import Test.Tasty
import Test.Tasty.Hspec
import Web.Page
import Web.Page.Examples
import qualified Data.Text.IO as Text

generatePage :: FilePath -> FilePath -> PageConfig -> Page -> IO ()
generatePage dir stem pc =
  renderPageToFile dir (#filenames .~ concernNames "" stem $ pc) 

generatePages ::
     Traversable t => FilePath -> t (FilePath, PageConfig, Page) -> IO ()
generatePages dir xs =
  void $ sequenceA $ (\(fp, pc, p) -> generatePage dir fp pc p) <$> xs

genTest :: FilePath -> IO ()
genTest dir =
  void $ generatePages dir [("default", defaultPageConfig, page1), ("sep", cfg2, page2)]

testVsFile :: FilePath -> FilePath -> PageConfig -> Page -> IO Bool
testVsFile dir stem pc p = do
  (t,t') <- textVsFile dir stem pc p
  pure (t==t')

textVsFile
  :: FilePath
  -> FilePath
  -> PageConfig
  -> Page
  -> IO (Concerns Text, Concerns Text)
textVsFile dir stem pc p = do
  let names = concernNames "" stem
  let pc' = #filenames .~ names $ pc
  let t = renderPageAsText pc' p
  case pc ^. #concerns of
    Inline -> do
      t' <- Text.readFile (dir <> names ^. #html)
      return (t, Concerns mempty mempty t')
    Separated -> do
      t' <- sequenceA $ Text.readFile <$> (dir <>) <$> names
      return (t, t')

testsRender :: IO (SpecWith ())
testsRender =
  return $
    describe "Web.Page.Render" $ do
      it "run genTest 'test/canned/' to refresh canned files." True
      it "renderPage mempty" $
        renderText (renderPage mempty) `shouldBe`
        "<!DOCTYPE HTML><html lang=\"en\"><head><meta charset=\"utf-8\"></head><body><script>window.onload=function(){}</script></body></html>"
      let dir = "test/canned/"
      it "renderPageToFile, renderPage (compared with default canned file)" $
        testVsFile dir "default" defaultPageConfig page1 `shouldReturn` True
      it "the various PageConfig's" $
        testVsFile dir "sep" cfg2 page2 `shouldReturn` True

testsBootstrap :: IO (SpecWith ())
testsBootstrap =
  return $
    describe "Web.Page.Bootstrap" $ do
      it "bootstrapPage versus canned" $
        toText (renderPage bootstrapPage) `shouldBe`
        "<!DOCTYPE HTML><html lang=\"en\"><head><meta charset=\"utf-8\"><link crossorigin=\"anonymous\" href=\"https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/css/bootstrap.min.css\" integrity=\"sha384-ggOyR0iXCbMQv3Xipma34MD+dH/1fQ784/j6cY/iJTQUOhcWr7x9JvoRxT2MZw1T\" rel=\"stylesheet\"><meta charset=\"utf-8\"><meta content=\"width=device-width, initial-scale=1, shrink-to-fit=no\" name=\"viewport\"></head><body><script crossorigin=\"anonymous\" integrity=\"sha384-q8i/X+965DzO0rT7abK41JStQIAqVgRVzpbzo5smXKp4YfRvH+8abtTE1Pi6jizo\" src=\"https://code.jquery.com/jquery-3.3.1.slim.min.js\"></script><script crossorigin=\"anonymous\" integrity=\"sha384-UO2eT0CpHqdSJQ6hJty5KVphtPhzWj9WO1clHTMGa3JDZwrnQq4sF86dIHNDz0W1\" src=\"https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.14.7/umd/popper.min.js\"></script><script crossorigin=\"anonymous\" integrity=\"sha384-JjSmVgyd0p3pXB1rRibZUAYoIIy6OrQ6VrjIEaFf/nJGzIxFDsf4x0xIM+B07jRM\" src=\"https://stackpath.bootstrapcdn.com/bootstrap/4.3.1/js/bootstrap.min.js\"></script><script>window.onload=function(){}</script></body></html>"
      it "accordion versus canned" $
        ( toText .
          runIdentity .
          flip evalStateT 0 .
          accordion "acctest" Nothing $
          (\x -> (Protolude.show x, "filler")) <$> [1..2::Int]) `shouldBe`
        "<div id=\"acctest1\" class=\" accordion \"><div class=\" card \"><div id=\"acctest2\" class=\" card-header \"><h2 class=\" mb-0 \"><button data-toggle=\"collapse\" data-target=\"#acctest3\" aria-controls=\"acctest3\" type=\"button\" class=\" btn btn-link collapsed \" aria-expanded=\"false\">1</button></h2></div><div data-parent=\"#acctest1\" id=\"acctest3\" aria-labelledby=\"acctest2\" class=\" collapse \"><div class=\" card-body \">filler</div></div></div><div class=\" card \"><div id=\"acctest4\" class=\" card-header \"><h2 class=\" mb-0 \"><button data-toggle=\"collapse\" data-target=\"#acctest5\" aria-controls=\"acctest5\" type=\"button\" class=\" btn btn-link collapsed \" aria-expanded=\"false\">2</button></h2></div><div data-parent=\"#acctest1\" id=\"acctest5\" aria-labelledby=\"acctest4\" class=\" collapse \"><div class=\" card-body \">filler</div></div></div></div>"

testsBridge :: IO (SpecWith ())
testsBridge =
  return $
    describe "Web.Page.Bridge" $
      it "bridgePage versus canned" $
        toText (renderPage bridgePage) `shouldBe`
        "<!DOCTYPE HTML><html lang=\"en\"><head><meta charset=\"utf-8\"></head><body><script>\nwindow.addEventListener('keydown',function(e) {\n  if(e.keyIdentifier=='U+000A' || e.keyIdentifier=='Enter' || e.keyCode==13) {\n    if(e.target.nodeName=='INPUT' && e.target.type !== 'textarea') {\n      e.preventDefault();\n      return false;\n    }\n  }\n}, true);\n window.onload=function(){\nwindow.jsb = {ws: new WebSocket('ws://' + location.host + '/')};\njsb.ws.onmessage = (evt) => eval(evt.data);\n};</script></body></html>"

testbs :: [Value]
testbs =
  [ Object (fromList [("element","1"),("value","b1")])
  , Object (fromList [("element","2"),("value","b2")])
  , Object (fromList [("element","3"),("value","b3")])
  ]

testvs :: [Value]
testvs =
  [ Object (fromList [("element","2"),("value","false")])
  , Object (fromList [("element","2"),("value","true")])
  , Object (fromList [("element","3"),("value","x")])
  , Object (fromList [("element","4"),("value","")])
  , Object (fromList [("element","5"),("value","2")])
  , Object (fromList [("element","6"),("value","0.6")])
  , Object (fromList [("element","7"),("value","false")])
  , Object (fromList [("element","8"),("value","true")])
  , Object (fromList [("element","9"),("value","5")])
  , Object (fromList [("element","10"),("value","#00b4cc")])
  ]

testsRep :: IO (SpecWith ())
testsRep =
  return $
    describe "Web.Page.Rep" $ do
      it "Rep mempty" $
        runIdentity (runList (pure (mempty :: Text)) []) `shouldBe` []
      it "mempty passes values through to hashmap" $
        runIdentity (runList (pure (mempty :: Text)) testbs) `shouldBe`
        [ Right (fromList [("1","b1")], Right "")
        , Right (fromList [("1","b1"),("2","b2")], Right "")
        , Right (fromList [("1","b1"),("2","b2"),("3","b3")], Right "")
        ]
      it "button consumes an event and the value is transitory" $
        runIdentity
        (runList
        ((,) <$> button Nothing <*> button Nothing)
        testbs) `shouldBe`
        [ Right (fromList [],Right (True,False))
        , Right (fromList [],Right (False,True))
        , Right (fromList [("3","b3")],Right (False,False))
        ]
      it "repExamples versus canned" $
        runIdentity (runOnce repExamples mempty) `shouldBe`
        (fromList [("7","3"),("1","sometext"),("4","0.5"),("2","no initial value & multi-line text\\nrenders is not ok?/"),("5","true"),("8","#3880c8"),("3","3"),("6","false")],Right (RepExamples {repTextbox = "sometext", repTextarea = "no initial value & multi-line text\\nrenders is not ok?/", repSliderI = 3, repSlider = 0.5, repCheckbox = True, repToggle = False, repDropdown = 3, repColor = PixelRGB8 56 128 200}))
      it "listifyExamples versus canned" $
        runIdentity (runOnce (listifyExample 5) mempty) `shouldBe`
        (fromList [("1","0"),("4","3"),("2","1"),("5","4"),("3","2"),("6","5")],Right [0,1,2,3,4,5])
      it "fiddleExample versus canned" $
        runIdentity (runOnce (repConcerns fiddleExample) mempty) `shouldBe`
        (fromList [("1",""),("2",""),("3","\n<div class=\" form-group-sm \"><label for=\"1\">fiddle example</label><input max=\"10.0\" value=\"3.0\" oninput=\"jsb.event({ &#39;element&#39;: this.id, &#39;value&#39;: this.value});\" step=\"1.0\" min=\"0.0\" id=\"1\" type=\"range\" class=\" custom-range  form-control-range \"></div>\n")],Right (Concerns "" "" "\n<div class=\" form-group-sm \"><label for=\"1\">fiddle example</label><input max=\"10.0\" value=\"3.0\" oninput=\"jsb.event({ &#39;element&#39;: this.id, &#39;value&#39;: this.value});\" step=\"1.0\" min=\"0.0\" id=\"1\" type=\"range\" class=\" custom-range  form-control-range \"></div>\n",False))

      it "repExamples run through some canned events" $
        runIdentity (runList (maybeRep Nothing True repExamples) testvs) `shouldBe`
        [Right (fromList [("7","true"),("4","no initial value & multi-line text\\nrenders is not ok?/"),("2","false"),("5","3"),("8","false"),("3","sometext"),("6","0.5"),("9","3"),("10","#3880c8")],Right Nothing),Right (fromList [("7","true"),("4","no initial value & multi-line text\\nrenders is not ok?/"),("2","true"),("5","3"),("8","false"),("3","sometext"),("6","0.5"),("9","3"),("10","#3880c8")],Right (Just (RepExamples {repTextbox = "sometext", repTextarea = "no initial value & multi-line text\\nrenders is not ok?/", repSliderI = 3, repSlider = 0.5, repCheckbox = True, repToggle = False, repDropdown = 3, repColor = PixelRGB8 56 128 200}))),Right (fromList [("7","true"),("4","no initial value & multi-line text\\nrenders is not ok?/"),("2","true"),("5","3"),("8","false"),("3","x"),("6","0.5"),("9","3"),("10","#3880c8")],Right (Just (RepExamples {repTextbox = "x", repTextarea = "no initial value & multi-line text\\nrenders is not ok?/", repSliderI = 3, repSlider = 0.5, repCheckbox = True, repToggle = False, repDropdown = 3, repColor = PixelRGB8 56 128 200}))),Right (fromList [("7","true"),("4",""),("2","true"),("5","3"),("8","false"),("3","x"),("6","0.5"),("9","3"),("10","#3880c8")],Right (Just (RepExamples {repTextbox = "x", repTextarea = "", repSliderI = 3, repSlider = 0.5, repCheckbox = True, repToggle = False, repDropdown = 3, repColor = PixelRGB8 56 128 200}))),Right (fromList [("7","true"),("4",""),("2","true"),("5","2"),("8","false"),("3","x"),("6","0.5"),("9","3"),("10","#3880c8")],Right (Just (RepExamples {repTextbox = "x", repTextarea = "", repSliderI = 2, repSlider = 0.5, repCheckbox = True, repToggle = False, repDropdown = 3, repColor = PixelRGB8 56 128 200}))),Right (fromList [("7","true"),("4",""),("2","true"),("5","2"),("8","false"),("3","x"),("6","0.6"),("9","3"),("10","#3880c8")],Right (Just (RepExamples {repTextbox = "x", repTextarea = "", repSliderI = 2, repSlider = 0.6, repCheckbox = True, repToggle = False, repDropdown = 3, repColor = PixelRGB8 56 128 200}))),Right (fromList [("7","false"),("4",""),("2","true"),("5","2"),("8","false"),("3","x"),("6","0.6"),("9","3"),("10","#3880c8")],Right (Just (RepExamples {repTextbox = "x", repTextarea = "", repSliderI = 2, repSlider = 0.6, repCheckbox = False, repToggle = False, repDropdown = 3, repColor = PixelRGB8 56 128 200}))),Right (fromList [("7","false"),("4",""),("2","true"),("5","2"),("8","true"),("3","x"),("6","0.6"),("9","3"),("10","#3880c8")],Right (Just (RepExamples {repTextbox = "x", repTextarea = "", repSliderI = 2, repSlider = 0.6, repCheckbox = False, repToggle = True, repDropdown = 3, repColor = PixelRGB8 56 128 200}))),Right (fromList [("7","false"),("4",""),("2","true"),("5","2"),("8","true"),("3","x"),("6","0.6"),("9","5"),("10","#3880c8")],Right (Just (RepExamples {repTextbox = "x", repTextarea = "", repSliderI = 2, repSlider = 0.6, repCheckbox = False, repToggle = True, repDropdown = 5, repColor = PixelRGB8 56 128 200}))),Right (fromList [("7","false"),("4",""),("2","true"),("5","2"),("8","true"),("3","x"),("6","0.6"),("9","5"),("10","#00b4cc")],Right (Just RepExamples {repTextbox = "x", repTextarea = "", repSliderI = 2, repSlider = 0.6, repCheckbox = False, repToggle = True, repDropdown = 5, repColor = PixelRGB8 0 180 204}))]

-- The tests
tests :: IO TestTree
tests = testGroup "the tests" <$> sequence
  [ testSpec "Web.Page.Render" =<< testsRender
  , testSpec "Web.Page.Bootstrap" =<< testsBootstrap
  , testSpec "Web.Page.Bridge" =<< testsBridge
  , testSpec "Web.Page.Rep" =<< testsRep
  ]

main :: IO ()
main = defaultMain =<< tests
