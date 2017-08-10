module CPU.Instructions (
    Instruction(..)
  , label
  , execute
  , instruction
  , opTable
    ) where

import BitTwiddling
import CPU.Types
import CPU.Environment
import CPU.Flags
import CPU.Arithmetic
import CPU
import ShowHex
import qualified Data.Bits as Bit
import Data.Word    

-- Instructions can have either 0, 1 or 2 bytes as arguments.
data Instruction s = Ary0 (CPU s Cycles)
                   | Ary1 (Word8 -> CPU s Cycles)
                   | Ary2 (Word16 -> CPU s Cycles)

data Operation s = Op { 
    label :: String, 
    instruction :: Instruction s 
}

opTable :: Opcode -> Operation s
opTable opcode = case opcode of
    0x00 -> Op "NOP"            $ Ary0 $ nop
    0x01 -> Op "LD BC,0x%04X"   $ Ary2 $ ld (directToCombo BC)
    0x05 -> Op "DEC B"          $ Ary0 $ dec b
    0x06 -> Op "LD B,0x%02X"    $ Ary1 $ ld (direct b)
    0x0D -> Op "DEC C"          $ Ary0 $ dec c
    0x0E -> Op "LD C,0x%02X"    $ Ary1 $ ld (direct c)
    0x20 -> Op "JR NZ,0x%02X"   $ Ary1 $ jr NZc
    0x21 -> Op "LD HL,0x%04X"   $ Ary2 $ ld (directToCombo HL)
    0x31 -> Op "LD SP,0x%04X"   $ Ary2 $ ld (direct16 sp)
    0x32 -> Op "LD (HL-),A"     $ Ary0 $ ld (derefMinus HL) =<< readReg a
    0x3E -> Op "LD A,0x%02X"    $ Ary1 $ ld (direct a)
    0x36 -> Op "LD (HL),0x%02X" $ Ary1 $ ld_deref_d8 HL
    0xAF -> Op "XOR A"          $ Ary0 $ xor =<< readReg a
    0xC3 -> Op "JP 0x%04X"      $ Ary2 $ jp
    0xE0 -> Op "LDH (0x%02X),A" $ Ary1 $ ldh_a8_reg a
    0xEA -> Op "LD (0x%04X),A"  $ Ary2 $ ld_a16_reg a
    0xF0 -> Op "LDH A,(0x%02X)" $ Ary1 $ ldh_reg_a8 a
    0xFE -> Op "CP 0x%02X"      $ Ary1 $ cp
    0xF3 -> Op "DI"             $ Ary0 $ di
    _    -> error $ "Unknown opcode " ++ (showHex opcode)

execute :: Instruction s -> CPU s Cycles
execute (Ary0 op) = op
execute (Ary1 op) = fetch >>= op
execute (Ary2 op) = fetch16 >>= op

-- Flag conditions, for instructions such as "JP NZ,A"

data FlagCondition = Cc | NCc | Zc | NZc | Any

condition :: FlagCondition -> CPU s Bool
condition fc = case fc of
    Cc  -> readFlag C
    NCc -> fmap not (readFlag C)
    Zc  -> readFlag Z
    NZc -> fmap not (readFlag Z)
    Any -> return True

-- Functions for loading to different destinations
direct :: CPURegister s Word8 -> Word8 -> CPU s Cycles
direct reg w =
    writeReg reg w >>
    return 8

direct16 :: CPURegister s Word16 -> (Word16 -> CPU s Cycles)
direct16 reg w = 
    writeReg reg w >>
    return 12

directToCombo :: ComboRegister -> (Word16 -> CPU s Cycles)
directToCombo reg = \w ->
    writeComboReg reg w >> 
    return 12 

-- e.g. LD (HL-) instructions.
-- Dereference the register, write the value to the address,
-- then decrement the register.
derefMinus :: ComboRegister -> Word8 -> CPU s Cycles
derefMinus reg w = do
    addr <- readComboReg reg
    writeMemory addr w
    writeComboReg reg (addr - 1)
    return 8

derefWrite :: ComboRegister -> Word8 -> CPU s ()
derefWrite reg w = do
    addr <- readComboReg reg
    writeMemory addr w

-- NOP: Blissfully let life pass you by.
nop :: CPU s Cycles
nop = return 4

-- JP: Unconditional jump to an address.
jp :: Address -> CPU s Cycles
jp addr = 
    writeReg pc addr >> 
    return 16

-- XOR: Exclusive-or the contents of A with the argument.
-- Sets flags: Z 0 0 0
xor :: Word8 -> CPU s Cycles
xor byte = do
    modifyReg a (Bit.xor byte) 
    -- Set the flags.
    a <- readReg a
    setFlags (As (a == 0), Off, Off, Off)
    return 4

-- LD: Load bytes into a destination.
ld :: (w -> CPU s Cycles) -> w -> CPU s Cycles
ld = id

ld_deref_d8 :: ComboRegister -> Word8 -> CPU s Cycles
ld_deref_d8 reg w8 = do
    derefWrite reg w8
    return 12

-- LDH (a8),reg: 
-- Load the contents of register into address (a8 + 0xFF00)
ldh_a8_reg :: CPURegister s Word8 -> Word8 -> CPU s Cycles
ldh_a8_reg reg a8 = do
    let addr = 0xFF00 + (fromIntegral a8 :: Word16)
    readReg reg >>= writeMemory addr
    return 12

-- LDH register,(a8): 
-- Load the contents of (a8 + 0xFF00) into register
ldh_reg_a8 :: CPURegister s Word8 -> Word8 -> CPU s Cycles
ldh_reg_a8 reg a8 = do
    let addr = 0xFF00 + (fromIntegral a8 :: Word16)
    readMemory addr >>= writeReg reg
    return 12

-- LD (a16),reg:
-- Load the contents of reg into the address (a16)
ld_a16_reg :: CPURegister s Word8 -> Word16 -> CPU s Cycles
ld_a16_reg reg a16 = do
    readReg reg >>= writeMemory a16
    return 16

-- DEC: Decrease a register or memory location by 1
-- Currently just the 8-bit registers.
-- Need to rethink this when I get to the others.
-- Flags: Z 1 H -
dec :: CPURegister s Word8 -> CPU s Cycles
dec reg = do
    modifyReg reg (subtract 1)
    v <- readReg reg
    setFlags (As (v == 0), On, Off, NA) -- half-carry is complicated, gonna ignore it right now
    return 4

-- CP: Compare with A to set flags.
-- Flags: Z 1 H C
cp :: Word8 -> CPU s Cycles
cp byte = do
    a <- readReg a
    let (result, c) = carriedSubtract a byte 
    setFlags (As (result == 0), On, Off, As c)
    return 8


-- JR: Relative conditional jump
-- cc is a flag condition. 
-- e is a *signed* 8-bit number.
--
-- If condition is met, PC := PC + e (12 cycles)
-- else                 continue     (8 cycles)
jr :: FlagCondition -> Word8 -> CPU s Cycles
jr cc byte = do
    jump <- condition cc
    if jump 
        then 
            modifyReg pc (+ signed) >>
            return 12                       
        else 
            return 8
            
    where signed = fromIntegral $ toSigned byte

-- DI: Disable interrupts
di :: CPU s Cycles
di = 
    disableMasterInterrupt >> 
    return 4 
