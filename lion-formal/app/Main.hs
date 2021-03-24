module Main where

import Development.Shake
import Development.Shake.FilePath
import Clash.Main (defaultMain)
import System.Directory (withCurrentDirectory)

formalTop :: String
formalTop = "LionFV"

buildDir :: FilePath
buildDir = "_build"

buildDir' :: FilePath -> FilePath
buildDir' = (buildDir </>)

verilog :: String -> FilePath
verilog top = "_build" </> top <.> "topEntity"

main :: IO ()
main = shakeArgs opts $ do
 
  want ["formal"]

  phony "clean" $ do
    putInfo "Cleaning files in _build"
    removeFilesAfter "_build" ["//*"]
    putInfo "Cleaning riscv-formal checks"
    removeFilesAfter "riscv-formal/cores/lion/checks" ["//*"]
    removeFilesAfter "riscv-formal/cores/lion/dmemcheck" ["//*"]
    removeFilesAfter "riscv-formal/cores/lion/imemcheck" ["//*"]
    removeFilesAfter "riscv-formal/cores/lion/complete" ["//*"]

  phony "formal" $ do
    putInfo "Formal Verification of Lion Core"
    need [verilog formalTop </> formalTop <.> "v"]

    -- generate checks
    liftIO $ withCurrentDirectory "riscv-formal/cores/lion" $
      cmd_ "python3" [".." </> ".." </> "checks" </> "genchecks.py"]

    -- gather checks
    checks <- getDirectoryFiles "riscv-formal/cores/lion/checks" ["//*.sby"]

    -- verify checks
    _ <- forP checks $ \check -> do
      let checkNoExt = dropExtensions check
      cmd_ "make" "-C" ["riscv-formal/cores/lion/checks"] [checkNoExt]
      need ["riscv-formal/cores/lion/checks" </> checkNoExt </> "PASS"]
      putInfo $ show checkNoExt ++ ": PASS"
    
    -- verify dmemcheck, imemcheck, complete
    liftIO $ withCurrentDirectory "riscv-formal/cores/lion" $ do
      cmd_ "sby" "dmemcheck.sby"
      cmd_ "sby" "imemcheck.sby"
      cmd_ "sby" "complete.sby"

    need ["riscv-formal/cores/lion/dmemcheck/PASS"]
    need ["riscv-formal/cores/lion/imemcheck/PASS"]
    need ["riscv-formal/cores/lion/complete/PASS"]

    putInfo "All formal checks PASS"
    
  -- build formal 
  verilog formalTop </> formalTop <.> "v" %> \_ ->
    liftIO $ compile formalTop

  where
    opts = shakeOptions
      { shakeFiles = buildDir
      , shakeThreads = 0
      }

compile :: String -> IO ()
compile topModule = defaultMain  ["-fclash-hdldir", buildDir, topModule, "--verilog"]
    
