-- | Download and import feeds from various sources.

module HN.Model.Feeds where

import HN.Data
import HN.Monads
import HN.Model.Items
import HN.Types
import HN.Curl

import Control.Applicative
import Network.URI
import Snap.App
import System.Locale
import Text.Feed.Import
import Text.Feed.Query
import Text.Feed.Types

-- | Get /r/haskell.
importRedditHaskell :: Model c s (Either String ())
importRedditHaskell = do
--  io $ putStr $ "Importing " ++ show Reddit ++ " ... "
  result <- io $ getReddit "haskell"
  case result of
    Left e -> return (Left e)
    Right items -> do
      mapM_ (addItem Reddit) items
      return (Right ())

-- | Import from proggit.
importProggit :: Model c s (Either String ())
importProggit = do
--  io $ putStr $ "Importing " ++ show Reddit ++ " ... "
  result <- io $ getReddit "programming"
  case result of
    Left e -> return (Left e)
    Right items -> do
      mapM_ (addItem Reddit) (filter (hasHaskell . niTitle) items)
      return (Right ())

  where hasHaskell = isInfixOf "haskell" . map toLower

importHaskellCafe = do
  importGenerically HaskellCafe
                    "https://groups.google.com/group/haskell-cafe/feed/rss_v2_0_msgs.xml"
                    (\item -> item { niTitle = strip (niTitle item) })

  where strip x | isPrefixOf "re: " (map toLower x) = strip (drop 4 x)
                | isPrefixOf label x = drop (length label) x
                | otherwise = x
        label = "[Haskell-cafe]"

importPlanetHaskell = do
  importGeneric PlanetHaskell "http://planet.haskell.org/rss20.xml"

importJobs = do
  importGeneric Jobs "http://www.haskellers.com/feed/jobs"

importStackOverflow = do
  importGeneric StackOverflow "http://stackoverflow.com/feeds/tag/haskell"
  importGeneric StackOverflow "http://programmers.stackexchange.com/feeds/tag/haskell"

-- | Import from Twitter search for "#haskell".
importTwitter :: Model c s (Either String ())
importTwitter = do
  importGeneric Twitter "http://search.twitter.com/search.rss?q=%23haskell"

importHaskellWiki =
  importGeneric HaskellWiki "http://www.haskell.org/haskellwiki/index.php?title=Special:Recentchanges&feed=rss"

importHackage =
  importGeneric Hackage "http://hackage.haskell.org/packages/archive/recent.rss"

-- | Import all vimeo content.
importVimeo :: Model c s (Either String ())
importVimeo = do
  importGeneric Vimeo "http://vimeo.com/channels/haskell/videos/rss"
  importGeneric Vimeo "http://vimeo.com/channels/galois/videos/rss"

-- | Import from a generic feed source.
importGeneric :: Source -> String -> Model c s (Either String ())
importGeneric source uri = do
  importGenerically source uri id

-- | Import from a generic feed source.
importGenerically :: Source -> String -> (NewItem -> NewItem) -> Model c s (Either String ())
importGenerically source uri f = do
--  io $ putStr $ "Importing " ++ show source ++ " ... "
  result <- io $ downloadFeed uri
  case result >>= mapM (fmap f . makeItem) . feedItems of
    Left e -> do
      return (Left e)
    Right items -> do
      mapM_ (addItem source) items
      return (Right ())

-- | Get Reddit feed.
getReddit :: String -> IO (Either String [NewItem])
getReddit subreddit = do
  result <- downloadFeed ("http://www.reddit.com/r/" ++ subreddit ++ "/.rss")
  case result of
    Left e -> return (Left e)
    Right e -> return (mapM makeItem (feedItems e))

-- | Make an item from a feed item.
makeItem :: Item -> Either String NewItem
makeItem item =
  NewItem <$> extract "item" (getItemTitle item)
          <*> extract "publish date" (getItemPublishDate item >>= parseDate)
          <*> extract "description" (getItemDescription item)
          <*> extract "link" (getItemLink item >>= parseURI)

  where extract label = maybe (Left ("unable to extract " ++ label)) Right

-- | Download and parse a feed.
downloadFeed :: String -> IO (Either String Feed)
downloadFeed uri = do
  result <- downloadString uri
  case result of
    Left e -> return (Left (show e))
    Right str -> case parseFeedString str of
      Nothing -> return (Left ("Unable to parse feed from: " ++ uri))
      Just feed -> return (Right feed)

parseDate x = parseRFC822 x <|> parseRFC3339 x

-- | Parse an RFC 3339 timestamp.
parseRFC3339 :: String -> Maybe ZonedTime
parseRFC3339 = parseTime defaultTimeLocale "%Y-%m-%dT%TZ"

-- | Parse an RFC 822 timestamp.
parseRFC822 :: String -> Maybe ZonedTime
parseRFC822 = parseTime defaultTimeLocale rfc822DateFormat
