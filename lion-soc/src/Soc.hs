{-|
Module      : Soc
Description : Lion SoC on the VELDT
Copyright   : (c) David Cox, 2021
License     : BSD-3-Clause
Maintainer  : standardsemiconductor@gmail.com
-}

module Soc where

import Clash.Prelude hiding ( fold )
import Clash.Annotations.TH
import Data.Functor ( (<&>) )
import Data.Foldable ( fold )
import Data.Maybe ( fromMaybe )
import Data.Monoid ( First(..) )
import Ice40.Clock
import Ice40.Rgb
import Ice40.Led
import Lion.Core (FromCore(..), defaultPipeConfig, core)
import Bus  ( mkBus, Bus(Bios, Led) )
import Uart ( uart )

data FromSoc dom = FromSoc
  { rgbOut :: "led"     ::: Signal dom Rgb
  , txOut  :: "uart_tx" ::: Signal dom Bit
  }

---------
-- RGB --
---------
type Rgb = ("red" ::: Bit, "green" ::: Bit, "blue" ::: Bit)

rgb :: HiddenClock dom => Signal dom (Maybe Bus) -> Signal dom Rgb
rgb mem = rgbPrim "0b0" "0b111111" "0b111111" "0b111111" (pure 1) (pure 1) r g b
  where
    (r, g, b, _) = led (pure 1) wr addr en (pure True)
    (wr, addr, en) = unbundle $ mem <&> \case
      Just (Led a d) -> (d, a, True )
      _              -> (0, 0, False)

----------
-- BIOS --
----------
bios
  :: HiddenClockResetEnable dom
  => Signal dom (Maybe Bus)
  -> Signal dom (First (BitVector 32))
bios mem = mux (delay False isValid) biosOut $ pure $ First Nothing
  where
    biosOut = fmap (First . Just) $ concat4 <$> b3 <*> b2 <*> b1 <*> b0
    b3 = romFilePow2 "_build/bios/bios.rom3" addr
    b2 = romFilePow2 "_build/bios/bios.rom2" addr
    b1 = romFilePow2 "_build/bios/bios.rom1" addr
    b0 = romFilePow2 "_build/bios/bios.rom0" addr
    (addr, isValid) = unbundle $ mem <&> \case
      Just (Bios a) -> (a, True )
      _             -> (0, False)

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
lion :: HiddenClockResetEnable dom => Signal dom Bit -> FromSoc dom
lion rxIn = FromSoc
  { rgbOut = fromRgb
  , txOut  = tx
  }
  where
    fromBios = bios fromCore
    fromRgb  = rgb  fromCore 
    (tx, fromUart) = uart fromCore rxIn
    fromCore = toMem $ core defaultCoreConfig $ 
      fmap (fromMaybe 0 . getFirst . fold) $ sequenceA $
           fromBios
        :> fromUart
        :> Nil 

----------------
-- Top Entity --
----------------
{-# NOINLINE topEntity #-}
topEntity 
  :: "clk"     ::: Clock Lattice12Mhz 
  -> "uart_rx" ::: Signal Lattice12Mhz Bit
  -> FromSoc Lattice12Mhz
topEntity clk = withClockResetEnable clk latticeRst enableGen lion
makeTopEntityWithName 'topEntity "Soc"
