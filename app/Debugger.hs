{-# LANGUAGE Rank2Types #-}

module Main where

import CPU
import CPU.Environment
import CPU.FrozenEnvironment
import qualified CPU.Instructions as Ops 
import CPURunner (step)
import CPU.Types
import Cartridge
import Viewers (viewCPU, viewStack)

import Control.Monad (liftM)
import Control.Monad.ST
import Data.Word
import Text.Printf

stepper :: FrozenCPUEnvironment -> Cycles -> IO ()
stepper cpuState cycles = do
    putStrLn (show cycles ++ " cycles elapsed\n")
    putStrLn $ viewCPU cpuState
    putStrLn "Press enter to step, or type 'QUIT' or 'MEM' > "
    command <- getLine
    case command of
        "" -> doStepFunc runStep
        "QUIT" -> putStrLn "Byee"
        "MEM"  -> putStrLn "Address: " >> readLn >>= printMem >> retry
        "STACK" -> putStrLn (viewStack cpuState) >> retry
        "RUN_TO" -> putStrLn "PC: " >> readLn >>= runToPc
        "RUN_FOR" -> putStrLn "Cycles: " >> readLn >>= runForCycles
        "STEP_OVER" -> runToNext >> retry
        "DUMP_VRAM" -> dumpVRAM cpuState >> retry
        _ -> putStrLn "Unknown command" >> retry
    
    where
        retry = stepper cpuState cycles
        printMem addr = putStrLn $ printf "[0x%02X] 0x%02X" addr (readFrzMemory addr cpuState)
        runToPc breakpoint = doStepFunc $ runCpu $ stepWhile (testPc (/= breakpoint))
        runToNext = runToPc (nextInstructionAddress cpuState)
        runForCycles num = doStepFunc $ runCpu $ stepWhileCycles (<= num)
        doStepFunc f =   
            let (nextState, extraCycles) = f cpuState
            in stepper nextState (cycles + extraCycles)

testPc :: (Word16 -> Bool) -> (CPU s Bool)
testPc f = readReg16 PC >>= return.f

nextInstructionAddress :: FrozenCPUEnvironment -> Address
nextInstructionAddress cpu =
    let pointer = frz_pc cpu
        opcode = readFrzMemory pointer cpu
        op = Ops.opTable opcode
    in case (Ops.instruction op) of
            (Ops.Ary0 _) -> pointer + 1
            (Ops.Ary1 _) -> pointer + 2
            (Ops.Ary2 _) -> pointer + 3
            (Ops.Unimplemented) -> pointer + 1

type StopCondition s = CPU s Bool
type CycleCountedComputation s = CPU s Int

stepWhile :: forall s. StopCondition s -> CycleCountedComputation s
stepWhile condition = stepWhile' 0
    where 
        stepWhile' sum = do
            continue <- condition
            if continue then
                step >>= stepWhile' . (sum +)
            else
                return sum

stepUntil :: forall s. StopCondition s -> CycleCountedComputation s
stepUntil condition = 
    stepWhile (liftM not condition)

stepWhileCycles :: (Int -> Bool) -> CycleCountedComputation s
stepWhileCycles condition = 
    stepWhileCycles' 0
    where 
        stepWhileCycles' sum 
            | condition sum = step >>= stepWhileCycles' . (sum +)
            | otherwise     = return sum

runCpu :: (forall s. CycleCountedComputation s) -> FrozenCPUEnvironment -> (FrozenCPUEnvironment, Cycles)
runCpu computation initialEnv = 
    runST $ resumeCPU initialEnv >>= runCPU (
        do
            cycles <- computation
            cpu <- extractEnvironment
            return (cpu, cycles)
    ) >>= pause

    where 
        pause (cpu,cycles) = do
            frozenCPU <- pauseCPU cpu
            return (frozenCPU, cycles)

runStep :: FrozenCPUEnvironment -> (FrozenCPUEnvironment, Cycles)
runStep = runCpu step

dumpVRAM :: FrozenCPUEnvironment -> IO ()
dumpVRAM  env = do
    let contents = foldl concattostring "" (frz_vram env) 
    writeFile "vram.txt" contents

    where concattostring s v = s ++ (show v)

main :: IO ()
main = do
    cpuState <- initCPU <$> romFromFile
    stepper cpuState 0
