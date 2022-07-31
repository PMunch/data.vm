import tables, endians, sequtils, random, bitops

type
  Chunk = ref seq[byte]
  Memory = Table[uint32, Chunk]
  Register = object
    chunk: Chunk
    position: int
    address: uint32

func encodedLen(value: int): int =
  if value == 0: return 1
  case value.countLeadingZeroBits():
  of 0..7: 9
  of 8..14: 8
  of 15..21: 7
  of 22..28: 6
  of 29..35: 5
  of 36..42: 4
  of 43..49: 3
  of 50..56: 2
  of 57..64: 1
  else: 0 # Shouldn't happen

proc encodeNumber*(val: SomeInteger): seq[byte] =
  # ZigZag
  when val is SomeSignedInt:
    var val = (val.int64 shl 1) xor (val.int64 shr 63)
  # Encode
  result.setLen val.int.encodedLen
  if result.len == 9: # Special case
    # High byte defaults to all 0's
    result[1..8] = cast[array[8, byte]](val)
  else:
    var encoded = ((val shl 1) or 1) shl (result.len - 1)
    result[0..^1] = cast[array[8, byte]](encoded)[0..result.high]

proc readSize(data: byte): int =
  if data == 0: 9
  else: data.countTrailingZeroBits() + 1

proc readNumber*(register: var Register, reset = false, signed = true): int =
  let length = readSize(register.chunk[register.position])
  if length == 9:
    result = cast[ptr int](register.chunk[register.position + 1].addr)[]
  else:
    cast[ptr array[8, byte]](result.addr)[0..<length] =
      register.chunk[register.position..<register.position + length]
    result = result shr length
  if signed:
    result = ((result shr 1) xor (if (result and 1) == 1: -1 else: 0))
  if not reset: register.position += length

template readUnsigned*(register: var Register, reset = false): uint =
  register.readNumber(reset, false).uint

proc writeMemory*(register: var Register, bytes: seq[byte], reset = false) =
  if register.position != register.chunk[].len:
    register.chunk[].insert(bytes, register.position)
  else:
    register.chunk[].add bytes
  if not reset:
    register.position += bytes.len

proc writeNumber*(register: var Register, num: SomeInteger, reset = false) =
  let bytes = encodeNumber(num)
  register.writeMemory bytes, reset

proc writeString*(register: var Register, str: string, reset = false) =
  let was = register.position
  for c in str:
    register.writeNumber(c.uint8)
  register.writeNumber 0
  if reset: register.position = was

proc readString*(register: var Register, reset = false): string =
  let was = register.position
  if register.chunk[].high < register.position: return ""
  var c = register.readNumber(signed = false)
  while c != 0:
    result &= c.char # TODO: Replace with Unicode handling
    c = register.readNumber(signed = false)
  if reset: register.position = was

proc skipNum*(register: var Register) =
  register.position += readSize(register.chunk[register.position])

proc skipStr*(register: var Register) =
  while register.position < register.chunk[].len:
    let length = readSize(register.chunk[register.position])
    if length == 1 and register.readNumber(signed = false) == 0: break
    else: register.position += length

proc deleteNum*(register: var Register) =
  let size = readSize(register.chunk[register.position])
  register.chunk[].delete(register.position..<(register.position + size))

proc deleteStr*(register: var Register) =
  let was = register.position
  while register.position < register.chunk[].len:
    let length = readSize(register.chunk[register.position])
    if length == 1 and register.readNumber(signed = false) == 0: break
    else: register.position += length
  register.chunk[].delete(was..register.position)

proc atomize*(x: string): uint32 =
  result = x.len.uint32 and 0x0fffffff'u32
  for c in x:
    result = (result shl 4) + c.uint32
    let g = result and 0xf0000000'u32
    if g != 0:
      result = result xor (g shr 24)
      result = result and (not g)

proc randomAddr(): uint32 =
  rand(268_435_455).uint32 # 2^28, the about of bits used in atoms

var memory: Memory

proc followChunk(register: var Register, address: SomeInteger = randomAddr()) =
  if not memory.hasKey address.uint32:
    memory[address.uint32] = new Chunk
  register.chunk = memory[address.uint32]
  register.position = 0
  register.address = address.uint32

import strutils

proc executeProcedure(x: string, args: var seq[byte]) =
  var regs = newSeq[Register](127)
  regs[0] = Register(chunk: memory[atomize(x)])
  const procReg = 0.uint
  regs[1].chunk = new Chunk
  regs[1].chunk[] = args
  while regs[procReg].position < regs[procReg].chunk[].len:
    let
      cmd = regs[procReg].readNumber(signed = false)
      reset = (cmd and 0b0100_0000) == 0
    template number(register: uint): untyped =
      let r = register
      regs[r].readNumber(reset and r != 0)
    template unsigned(register: uint): untyped =
      let r = register
      regs[r].readUnsigned(reset and r != 0)
    template string(register: uint): untyped =
      let r = register
      regs[r].readString(reset and r != 0)
    echo "Executing command: ", cmd.toBin(8)
    case (cmd and 0b0011_1000) shr 3:
    of 0b000: # Jump instructions
      var
        jump = false
        target: uint32
        position = 0
      case cmd and 0b0000_0111:
      of 0b000:
        let reg = procReg.unsigned
        regs[reg].position = regs[reg].chunk[].len
      of 0b001:
        jump = true
        target = procReg.unsigned.uint32
        position = procReg.unsigned.int
      of 0b010..0b111:
        let
          a = procReg.unsigned.number
          b = procReg.unsigned.number
        target = procReg.unsigned.uint32
        case cmd and 0b0000_0111:
        of 0b010:
          if a == b: jump = true
        of 0b011:
          if a != b: jump = true
        of 0b100:
          if a < b: jump = true
        of 0b101:
          if a > b: jump = true
        of 0b110: discard # floats
        of 0b111: discard # floats
        else: discard
      else: discard
      if jump:
        regs[procReg] = Register(chunk: memory[target], position: position)
    of 0b001: # Copy instructions
      case cmd and 0b0000_0111:
      of 0b000:
        let
          aReg = procReg.unsigned
          bReg = procReg.unsigned
        regs[aReg].writeNumber(regs[bReg].readNumber(reset and (bReg != 0)), reset and (aReg != 0))
      of 0b001:
        let
          aReg = procReg.unsigned
          bReg = procReg.unsigned
          c = procReg.unsigned
          aWas = regs[aReg].position
          bWas = regs[bReg].position
        for i in 0..<c:
          regs[aReg].writeNumber(regs[bReg].readNumber)
        if reset:
          if aReg != 0: regs[aReg].position = aWas
          if bReg != 0: regs[bReg].position = bWas
      of 0b010:
        let
          aReg = procReg.unsigned
          bReg = procReg.unsigned
          aWas = regs[aReg].position
          bWas = regs[bReg].position
        while true:
          let num = regs[bReg].readNumber
          if num == 0: break
          regs[aReg].writeNumber(num)
        if reset:
          if aReg != 0: regs[aReg].position = aWas
          if bReg != 0: regs[bReg].position = bWas
      else: discard
    of 0b010: # Follow instructions
      case cmd and 0b0000_0111:
      of 0b000:
        regs[procReg.unsigned].followChunk(procReg.unsigned.unsigned)
      of 0b001:
        regs[procReg.unsigned].followChunk
      else: discard
    of 0b011: # Skip instructions
      case cmd and 0b0000_0111:
      of 0b000:
        regs[procReg.unsigned].skipNum
      of 0b001:
        let
          reg = procReg.unsigned
          count = procReg.unsigned
        for i in 0..<count:
          regs[reg].skipNum
      of 0b010:
        regs[procReg.unsigned].skipStr
      else: discard
    of 0b100: # Arithmetic instructions
      case cmd and 0b0000_0111:
      of 0b000:
        regs[procReg.unsigned].writeNumber(procReg.unsigned.unsigned + procReg.unsigned.unsigned, reset)
      of 0b001:
        regs[procReg.unsigned].writeNumber(procReg.unsigned.unsigned - procReg.unsigned.unsigned, reset)
      of 0b010:
        regs[procReg.unsigned].writeNumber(procReg.unsigned.unsigned * procReg.unsigned.unsigned, reset)
      of 0b011:
        regs[procReg.unsigned].writeNumber(procReg.unsigned.unsigned div procReg.unsigned.unsigned, reset)
      of 0b100:
        regs[procReg.unsigned].writeNumber(procReg.unsigned.number + procReg.unsigned.number, reset)
      of 0b101:
        regs[procReg.unsigned].writeNumber(procReg.unsigned.number - procReg.unsigned.number, reset)
      of 0b110:
        regs[procReg.unsigned].writeNumber(procReg.unsigned.number * procReg.unsigned.number, reset)
      of 0b111:
        regs[procReg.unsigned].writeNumber(procReg.unsigned.number div procReg.unsigned.number, reset)
      else: discard
    of 0b111: # Misc instructions
      case cmd and 0b0000_0111:
      of 0b000:
        regs[procReg.unsigned].deleteNum
      of 0b001:
        let
          reg = procReg.unsigned
          count = procReg.unsigned
        for i in 0..<count:
          regs[reg].deleteNum
      of 0b010:
        regs[procReg.unsigned].deleteStr
      of 0b011:
        regs[procReg.unsigned].position = 0
      of 0b100:
        regs[procReg.unsigned].writeNumber(regs[procReg.unsigned].address, reset)
      of 0b101:
        regs[procReg.unsigned].writeNumber(regs[procReg.unsigned].position, reset)
      else: discard
    else: discard
  args = regs[1].chunk[]

proc executeProcedureStr(x: string, arg: string) =
  var argBytes = newSeqOfCap[byte](arg.len + 1)
  for c in arg:
    argBytes.add c.uint8.encodeNumber
  argBytes.add 0.encodeNumber
  executeProcedure(x, argBytes)

var
  register: Register # = Register(chunk: chunk, position: 0)
  listRegister: Register # = Register(chunk: chunk, position: 0)

register.followChunk(atomize("add task"))
register.writeNumber 0b00_010_001'u # Follow new chunk
register.writeNumber 2'u # In register 2
register.writeNumber 0b01_001_010'u # Copy string from register to register
register.writeNumber 2'u # To register 2
register.writeNumber 1'u # From register 1
register.writeNumber 0b01_001_000'u # Copy int from register to register
register.writeNumber 2'u # To register 2
register.writeNumber 0'u # From procedure register
register.writeNumber 0'u # Literal number 0 (to terminate string)
register.writeNumber 0b01_001_000'u # Copy int to register
register.writeNumber 2'u # To register 2
register.writeNumber 0'u # From procedure register
register.writeNumber 0'u # Literal number 0
register.writeNumber 0b01_001_000'u # Copy int to register
register.writeNumber 2'u # To register 2
register.writeNumber 0'u # From procedure register
register.writeNumber 0'u # Literal number 0
register.writeNumber 0b00_010_000'u # Follow given chunk
register.writeNumber 3'u # In register 3
register.writeNumber 0'u # Read from procedure register
register.writeNumber atomize("task list")
register.writeNumber 0b00_111_100'u # Write register address to register
register.writeNumber 3'u # To register 3
register.writeNumber 2'u # Address of register 2

when false:
  import macros

  macro datavm(y: string, x: untyped): untyped =
    echo x.treeRepr
    let register = genSym(nskVar, "register")
    result = quote do:
      var `register`: Register
      `register`.followChunk(atomize(`y`))
    for command in x:
      case $command[0]:
      of "jumpToEnd", "jen":
        let arg = command[1].intVal.uint64
        result.add quote do:
          `register`.writeNumber 0b00_000_000'u
          `register`.writeNumber `arg`
      of "jumpTo", "jum": discard
      of "jumpEquals", "jeq": discard
      of "jumpNotEquals", "jne": discard
      of "jumpLessThan", "jlt": discard
      of "jumpMoreThan", "jmt": discard
      of "copyInt", "cit": discard
      of "copyN", "cni": discard
      of "copyString", "cst": discard
      of "follow", "flw": discard
      of "followNew", "fln": discard
      of "skipInt", "sit": discard
      of "skipN", "sni": discard
      of "skipString", "sst": discard
      of "add": discard
      of "subtract", "sub": discard
      of "multiply", "mul": discard
      of "divide", "div": discard
      of "deleteInt", "dit": discard
      of "deleteN", "dni": discard
      of "deleteString", "dst": discard
      of "resetRegister", "rrg": discard
      of "putAddress", "pad": discard
      of "putPosition", "ppo": discard
      else: raise newException(ValueError, "Unknown command: " & $command[0])

  datavm("get tasks"):
    followNew 2
    copyString 2, 1
    copyInt 2, !0
    copyInt 2, !0
    follow 3, !"task list"
    putAddress 3, 2

register.followChunk(atomize("get tasks"))
register.writeNumber 0b01_001_000'u # Copy number
register.writeNumber 1'u # To output register
register.writeNumber 0'u # From this register
register.writeNumber 91'u # Character
register.writeNumber 0b00_010_000'u # Follow given chunk
register.writeNumber 2'u # In register 2
register.writeNumber 0'u # From this register
register.writeNumber atomize("task list")
register.writeNumber 0b00_000_010'u # Jump if equal, don't advance
register.writeNumber 2'u # Number in task list
register.writeNumber 0'u # Number from this register
register.writeNumber 0'u # Zero value, end-of-list
register.writeNumber atomize("get tasks end")
register.writeNumber 0b00_000_001'u # Jump to chunk
register.writeNumber atomize("get tasks loop")
register.writeNumber 0'u # At position 0

register.followChunk(atomize("get tasks loop"))
register.writeNumber 0b01_010_000'u # Follow read chunk
register.writeNumber 3'u # In register 3
register.writeNumber 2'u # From register 2 (set up to track task list)
register.writeNumber 0b01_001_010'u # Copy string
register.writeNumber 1'u # To output register
register.writeNumber 0'u # From this register
register.writeString "{\"name\":\""
register.writeNumber 0b01_001_010'u # Copy string
register.writeNumber 1'u # To output register
register.writeNumber 3'u # From register 3
register.writeNumber 0b01_001_010'u # Copy string
register.writeNumber 1'u # To output register
register.writeNumber 0'u # From this register
register.writeString "\"}"
register.writeNumber 0b01_011_001'u # Skip ints
register.writeNumber 3'u # In register 3
register.writeNumber 2'u # 2 numbers
register.writeNumber 0b00_000_010'u # Jump if equal, don't advance
register.writeNumber 2'u # Number in task list
register.writeNumber 0'u # Number from this register
register.writeNumber 0'u # Zero value, end-of-list
register.writeNumber atomize("get tasks end")
register.writeNumber 0b01_001_010'u # Copy string
register.writeNumber 1'u # To output register
register.writeNumber 0'u # From this register
register.writeString ","
register.writeNumber 0b00_000_001'u # Jump to register
register.writeNumber atomize("get tasks loop")
register.writeNumber 0'u # At position 0

register.followChunk(atomize("get tasks end"))
register.writeNumber 0b01_001_010'u # Copy string
register.writeNumber 1'u # To output register
register.writeNumber 0'u # From this register
register.writeString "]"
register.writeNumber 0b01_001_000'u # Copy string
register.writeNumber 1'u # To output register
register.writeNumber 0'u # From this register
register.writeNumber 0'u

# TODO: Implement the rest of this function
# TODO: Write macro for parsing an assembly language
# TODO: Write better procedure for calling and getting return value from procs

listRegister.followChunk(atomize("task list"))
listRegister.writeNumber 0'u
listRegister.position = 0
register.followChunk
register.writeString "This is the first task"
register.writeNumber 0'u
register.writeNumber 0'u
listRegister.writeNumber register.address
register.followChunk
register.writeString "This is the second task"
register.writeNumber 0'u
register.writeNumber 0'u
listRegister.writeNumber register.address

executeProcedureStr("add task", "This is the third task")

echo register.chunk[]
echo listRegister.chunk[]
listRegister.position = 0
var num = listRegister.readNumber(signed = false)
while num != 0:
  #echo memory[num.uint32][]
  echo num
  register.followChunk(num)
  echo register.chunk[]
  echo "Task: ", register.readString, ", status: ", register.readNumber, ", completed at: ", register.readNumber
  num = listRegister.readNumber(signed = false)

var size = 0
for address, chunk in memory:
  echo "Chunk ", address.toHex, ": ", address.encodeNumber.len, " + ", chunk[].len
  size += address.encodeNumber.len
  size += chunk[].len

echo "Final size: ", size

var returnVal: seq[byte]
executeProcedure("get tasks", returnVal)
echo returnVal
register.position = 0
register.chunk[] = returnVal
echo register.readString
