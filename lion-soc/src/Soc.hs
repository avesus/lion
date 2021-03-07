{-|
Module      : Soc
Description : Lion SoC on the VELDT
Copyright   : (c) David Cox, 2021
License     : BSD-3-Clause
Maintainer  : standardsemiconductor@gmail.com
-}

module Soc where

import Clash.Prelude
import Clash.Annotations.TH
import Data.Functor ( (<&>) )
import Data.Maybe ( fromMaybe )
import Ice40.Clock
import Ice40.Rgb
import Ice40.Led
import Lion.Core

---------
-- RGB --
---------
type Rgb = ("red" ::: Bit, "green" ::: Bit, "blue" ::: Bit)

rgb :: HiddenClock dom => Signal dom (Maybe ToMem) -> Signal dom Rgb
rgb mem = rgbPrim "0b0" "0b111111" "0b111111" "0b111111" (pure 1) (pure 1) r g b
  where
    (wr, addr, en) = unbundle $ mem <&> \case
      Just (DataMem 
              $(bitPattern "00000000000000000000000100000000")
              $(bitPattern "0011")
              (Just d)
           ) -> (slice d7 d0 d, slice d11 d8 d, True)
      _ -> (0, 0, False)
    (r, g, b, _) = led (pure 1) wr addr en (pure True)

----------
-- BIOS --
----------
bios
  :: HiddenClockResetEnable dom
  => Signal dom (Maybe ToMem)
  -> Signal dom (BitVector 32)
bios mem = concat4 <$> b3 <*> b2 <*> b1 <*> b0
  where
    addr = unpack . slice d7 d0 . (`shiftR` 2) . fromMaybe 0 . fmap getAddr <$> mem
    b3 = romFilePow2 "_build/bios/bios.rom3" addr
    b2 = romFilePow2 "_build/bios/bios.rom2" addr
    b1 = romFilePow2 "_build/bios/bios.rom1" addr
    b0 = romFilePow2 "_build/bios/bios.rom0" addr
    getAddr = \case
      InstrMem a    -> a
      DataMem a _ _ -> a

concat4
  :: KnownNat n
  => BitVector n
  -> BitVector n
  -> BitVector n
  -> BitVector n
  -> BitVector (4 * n)
concat4 b3 b2 b1 b0 = b3 ++# b2 ++# b1 ++# b0

--------------
-- Lion SOC --
--------------
lion :: HiddenClockResetEnable dom => Signal dom Rgb
lion = rgb $ toMem fromCore
  where
    fromCore = core defaultCoreConfig fromBios
    fromBios = bios $ toMem fromCore
    
----------------
-- Top Entity --
----------------
{-# NOINLINE topEntity #-}
topEntity :: "clk" ::: Clock Lattice12Mhz -> "led" ::: Signal Lattice12Mhz Rgb
topEntity clk = withClockResetEnable clk latticeRst enableGen lion
makeTopEntityWithName 'topEntity "Soc"
