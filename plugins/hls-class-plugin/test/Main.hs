{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedLabels  #-}
{-# LANGUAGE OverloadedLists   #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators     #-}
{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -Wno-incomplete-uni-patterns #-}

module Main
  ( main
  ) where

import           Control.Lens                  (Prism', prism', (^.), (^..),
                                                (^?))
import           Control.Monad                 (void)
import           Data.Maybe
import           Data.Row                      ((.==))
import qualified Data.Text                     as T
import qualified Ide.Plugin.Class              as Class
import qualified Language.LSP.Protocol.Lens    as L
import           Language.LSP.Protocol.Message
import           System.FilePath
import           Test.Hls

main :: IO ()
main = defaultTestRunner tests

classPlugin :: PluginTestDescriptor Class.Log
classPlugin = mkPluginTestDescriptor Class.descriptor "class"

tests :: TestTree
tests = testGroup
  "class"
  [ codeActionTests
  , codeLensTests
  ]

codeActionTests :: TestTree
codeActionTests = testGroup
  "code actions"
  [ expectCodeActionsAvailable "Produces addMinimalMethodPlaceholders code actions for one instance" "T1"
      [ "Add placeholders for '=='"
      , "Add placeholders for '==' with signature(s)"
      , "Add placeholders for '/='"
      , "Add placeholders for '/=' with signature(s)"
      , "Add placeholders for all missing methods"
      , "Add placeholders for all missing methods with signature(s)"
      ]
  , goldenWithClass "Creates a placeholder for '=='" "T1" "eq" $ \(eqAction:_) -> do
      executeCodeAction eqAction
  , goldenWithClass "Creates a placeholder for '/='" "T1" "ne" $ \(_:_:neAction:_) -> do
      executeCodeAction neAction
  , goldenWithClass "Creates a placeholder for both '==' and '/='" "T1" "all" $ \(_:_:_:_:allMethodsAction:_) -> do
      executeCodeAction allMethodsAction
  , goldenWithClass "Creates a placeholder for 'fmap'" "T2" "fmap" $ \(_:_:_:_:_:_:fmapAction:_) -> do
      executeCodeAction fmapAction
  , goldenWithClass "Creates a placeholder for multiple methods 1" "T3" "1" $ \(mmAction:_) -> do
      executeCodeAction mmAction
  , goldenWithClass "Creates a placeholder for multiple methods 2" "T3" "2" $ \(_:_:mmAction:_) -> do
      executeCodeAction mmAction
  , goldenWithClass "Creates a placeholder for a method starting with '_'" "T4" "" $ \(_fAction:_) -> do
      executeCodeAction _fAction
  , goldenWithClass "Creates a placeholder for '==' with extra lines" "T5" "" $ \(eqAction:_) -> do
      executeCodeAction eqAction
  , goldenWithClass "Creates a placeholder for only the unimplemented methods of multiple methods" "T6" "1" $ \(gAction:_) -> do
      executeCodeAction gAction
  , goldenWithClass "Creates a placeholder for other two methods" "T6" "2" $ \(_:_:ghAction:_) -> do
      executeCodeAction ghAction
  , onlyRunForGhcVersions [GHC92, GHC94] "Only ghc-9.2+ enabled GHC2021 implicitly" $
      goldenWithClass "Don't insert pragma with GHC2021" "InsertWithGHC2021Enabled" "" $ \(_:eqWithSig:_) -> do
        executeCodeAction eqWithSig
  , goldenWithClass "Insert pragma if not exist" "InsertWithoutPragma" "" $ \(_:eqWithSig:_) -> do
      executeCodeAction eqWithSig
  , goldenWithClass "Don't insert pragma if exist" "InsertWithPragma" "" $ \(_:eqWithSig:_) -> do
      executeCodeAction eqWithSig
  , goldenWithClass "Only insert pragma once" "InsertPragmaOnce" "" $ \(_:multi:_) -> do
      executeCodeAction multi
  , expectCodeActionsAvailable "No code action available when minimal requirements meet" "MinimalDefinitionMeet" []
  , expectCodeActionsAvailable "Add placeholders for all missing methods is unavailable when all methods are required" "AllMethodsRequired"
      [ "Add placeholders for 'f','g'"
      , "Add placeholders for 'f','g' with signature(s)"
      ]
  , testCase "Update text document version" $ runSessionWithServer classPlugin testDataDir $ do
    doc <- createDoc "Version.hs" "haskell" "module Version where"
    ver1 <- (^. L.version) <$> getVersionedDoc doc
    liftIO $ ver1 @?= 0

    -- Change the doc to ensure the version is not 0
    changeDoc doc
        [ TextDocumentContentChangeEvent . InR . (.==) #text $
            T.unlines ["module Version where", "data A a = A a", "instance Functor A where"]
        ]
    ver2 <- (^. L.version) <$> getVersionedDoc doc
    _ <- waitForDiagnostics
    liftIO $ ver2 @?= 1

    -- Execute the action and see what the version is
    action <- head . concatMap (^.. _CACodeAction) <$> getAllCodeActions doc
    executeCodeAction action
    _ <- waitForDiagnostics
    -- TODO: uncomment this after lsp-test fixed
    -- ver3 <- (^.J.version) <$> getVersionedDoc doc
    -- liftIO $ ver3 @?= Just 3
    pure mempty
  ]

codeLensTests :: TestTree
codeLensTests = testGroup
    "code lens"
    [ testCase "Has code lens" $ do
        runSessionWithServer classPlugin testDataDir $ do
            doc <- openDoc "CodeLensSimple.hs" "haskell"
            lens <- getCodeLenses doc
            let titles = map (^. L.title) $ mapMaybe (^. L.command) lens
            liftIO $ titles @?=
                [ "(==) :: B -> B -> Bool"
                , "(==) :: A -> A -> Bool"
                ]
    , testCase "No lens for TH" $ do
        runSessionWithServer classPlugin testDataDir $ do
            doc <- openDoc "TH.hs" "haskell"
            lens <- getCodeLenses doc
            liftIO $ length lens @?= 0
    , goldenCodeLens "Apply code lens" "CodeLensSimple" 1
    , goldenCodeLens "Apply code lens for local class" "LocalClassDefine" 0
    , goldenCodeLens "Apply code lens on the same line" "Inline" 0
    , goldenCodeLens "Don't insert pragma while existing" "CodeLensWithPragma" 0
    , onlyRunForGhcVersions [GHC92, GHC94] "Only ghc-9.2+ enabled GHC2021 implicitly" $
        goldenCodeLens "Don't insert pragma while GHC2021 enabled" "CodeLensWithGHC2021" 0
    , goldenCodeLens "Qualified name" "Qualified" 0
    , goldenCodeLens "Type family" "TypeFamily" 0
    , testCase "keep stale lens" $ do
        runSessionWithServer classPlugin testDataDir $ do
            doc <- openDoc "Stale.hs" "haskell"
            oldLens <- getCodeLenses doc
            let edit = TextEdit (mkRange 4 11 4 12) "" -- Remove the `_`
            _ <- applyEdit doc edit
            newLens <- getCodeLenses doc
            liftIO $ newLens @?= oldLens
    ]

_CACodeAction :: Prism' (Command |? CodeAction) CodeAction
_CACodeAction = prism' InR $ \case
  InR action -> Just action
  _          -> Nothing

goldenCodeLens :: TestName -> FilePath -> Int -> TestTree
goldenCodeLens title path idx =
    goldenWithHaskellDoc classPlugin title testDataDir path "expected" "hs" $ \doc -> do
        lens <- getCodeLenses doc
        executeCommand $ fromJust $ (lens !! idx) ^. L.command
        void $ skipManyTill anyMessage (message SMethod_WorkspaceApplyEdit)

goldenWithClass ::TestName -> FilePath -> FilePath -> ([CodeAction] -> Session ()) -> TestTree
goldenWithClass title path desc act =
  goldenWithHaskellDoc classPlugin title testDataDir path (desc <.> "expected") "hs" $ \doc -> do
    _ <- waitForDiagnosticsFromSource doc "typecheck"
    actions <- concatMap (^.. _CACodeAction) <$> getAllCodeActions doc
    act actions
    void $ skipManyTill anyMessage (getDocumentEdit doc)

expectCodeActionsAvailable :: TestName -> FilePath -> [T.Text] -> TestTree
expectCodeActionsAvailable title path actionTitles =
  testCase title $ do
    runSessionWithServer classPlugin testDataDir $ do
      doc <- openDoc (path <.> "hs") "haskell"
      _ <- waitForDiagnosticsFromSource doc "typecheck"
      caResults <- getAllCodeActions doc
      liftIO $ map (^? _CACodeAction . L.title) caResults
        @?= expectedActions
    where
      expectedActions = Just <$> actionTitles

testDataDir :: FilePath
testDataDir = "test" </> "testdata"
