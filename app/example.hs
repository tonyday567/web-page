{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wall #-}

import NumHask.Prelude
import Options.Generic
import Web.Page
import Web.Page.Examples

data AppType = SharedTest deriving (Eq, Read, Show, Generic)

instance ParseField AppType

instance ParseRecord AppType

instance ParseFields AppType

data Opts w
  = Opts
      { apptype :: w ::: AppType <?> "type of example"
      }
  deriving (Generic)

instance ParseRecord (Opts Wrapped)

main :: IO ()
main = do
  o :: Opts Unwrapped <- unwrapRecord "examples for web-page"
  case apptype o of
      SharedTest -> defaultSharedServer (maybeRep (Just "maybe") False repExamples)
