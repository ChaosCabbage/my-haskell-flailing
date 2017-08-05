module Viewers (
    viewCPU
  , viewStack
  , viewMem
  , viewMem16
) where

import CPU.FrozenEnvironment (FrozenCPUEnvironment(..), readFrzMemory)
import CPU.Types (Address)
import BitTwiddling (joinBytes)
import Text.Printf (printf)
import Data.Word (Word8, Word16)
import Data.Bits (testBit)
import Data.Array ((!))

-- A basic view showing the registers, flags and the next instruction:
--
--     A F  B C  D E  H L   SP
--     01B0 0013 00D8 014D FFFE
--
--                       IME : ENABLED
--     Flags ZNHC         
--           1011          
--
--     PC = 0x0100 (0x00)
--
viewCPU :: FrozenCPUEnvironment -> String
viewCPU cpu = 
            "A F  B C  D E  H L   SP \n" ++
    (printf "%02X%02X %02X%02X %02X%02X %02X%02X %04X\n\n" 
        (frz_a cpu) (frz_f cpu) (frz_b cpu) (frz_c cpu) (frz_d cpu) (frz_e cpu) (frz_h cpu) (frz_l cpu) (frz_sp cpu)) ++
    ("                  IME: " ++ (if frz_ime cpu then "ENABLED" else "DISABLED")) ++ "\n" ++
    (viewFlags $ frz_f cpu) ++
    "\n" ++
    (printf "PC = 0x%04X (0x%02X)\n" (frz_pc cpu) (frz_rom00 cpu ! (frz_pc cpu)))

viewFlags :: Word8 -> String
viewFlags f = 
    "Flags ZNHC \n" ++ 
    "      " ++ (b 7) ++ (b 6) ++ (b 5) ++ (b 4) ++ "\n"
    where 
        b n = if (testBit f n) then "1" else "0"

readMem16 :: Address -> FrozenCPUEnvironment -> Word16
readMem16 address cpu = 
    let
        low = readFrzMemory address cpu
        high = readFrzMemory (address + 1) cpu
    in
        joinBytes low high

viewMem16 :: Address -> FrozenCPUEnvironment -> String
viewMem16 address cpu = 
    printf "0x%04X" $ readMem16 address cpu 

viewMem :: Address -> FrozenCPUEnvironment -> String
viewMem address cpu = 
    printf "0x%02X" $ readFrzMemory address cpu

viewStack :: FrozenCPUEnvironment -> String
viewStack cpu =
    (traceStackFrom 0xFFFE) ++ (showPointer)
    where
        pointer = frz_sp cpu
        showPointer = printf "[    ] <- 0x%04X\n" pointer
        traceStackFrom address 
            | address > pointer = (viewMem16 address cpu) ++ "\n" ++ 
                                  (traceStackFrom (address - 2))
            | otherwise = ""