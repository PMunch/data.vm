import tables, endians, sequtils, random, bitops

type
  Chunk = ref seq[byte]
  Memory = Table[uint32, Chunk]
  Register = object
    chunk: Chunk
    position: int
    address: uint32

when true:
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
    var val = (val.int64 shl 1) xor (val.int64 shr 63)
    # Encode
    result.setLen val.int.encodedLen
    if result.len == 9: # Special case
      # High byte defaults to all 0's
      #swapEndian64(val.unsafeaddr, val.unsafeaddr)
      result[1..8] = cast[array[8, byte]](val)
    else:
      var encoded = ((val shl 1) or 1) shl (result.len - 1)
      result[0..^1] = cast[array[8, byte]](encoded)[0..result.high]

  proc readSize(data: byte): int =
    if data == 0: 9
    else: data.countTrailingZeroBits() + 1

  proc readNumber*(register: var Register, reset = false): int =
    let length = readSize(register.chunk[register.position])
    if length == 9:
      result = cast[ptr int](register.chunk[register.position + 1].addr)[]
      #swapEndian64(result.addr, result.addr)
    else:
      cast[ptr array[8, byte]](result.addr)[0..<length] =
        register.chunk[register.position..<register.position + length]
      result = result shr length
    result = ((result shr 1) xor (if (result and 1) == 1: -1 else: 0))
    if not reset: register.position += length
else:
  proc hob(x: int): uint =
    result = x.uint
    result = result or (result shr 1)
    result = result or (result shr 2)
    result = result or (result shr 4)
    result = result or (result shr 8)
    result = result or (result shr 16)
    result = result or (result shr 32)
    result = result - (result shr 1)

  proc encodeNumber*(val: SomeInteger): seq[byte] =
    var t = val.int * 2
    if val < 0:
      t = t xor -1
    var
      bytes = t.hob shr 7
      num = t
    result.add (num and 0x7f or (if bytes != 0: 0x80 else: 0)).byte
    while bytes != 0:
      num = num shr 7
      bytes = bytes shr 7
      result.add (num and 0x7f or (if bytes != 0: 0x80 else: 0)).byte

  proc readNumber*(register: var Register, reset = false): int =
    let was = register.position
    if register.chunk[].high < register.position: return 0
    var
      byte = register.chunk[register.position].uint8
      i = 1
    inc register.position
    result = (byte and 0x7f).int
    while (byte and 0x80) != 0:
      # TODO: Add error checking for values not fitting 64 bits
      byte = register.chunk[register.position].uint8
      inc register.position
      result = result or ((byte and 0x7f).int shl (7*i))
      i += 1
    result = ((result shr 1) xor (if (result and 1) == 1: -1 else: 0))
    if reset: register.position = was

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
  register.writeMemory cast[seq[byte]](str)
  register.writeMemory @[0.byte]
  if reset: register.position = was

proc readString*(register: var Register, reset = false): string =
  let was = register.position
  if register.chunk[].high < register.position: return ""
  var
    c = register.chunk[register.position]
  while c != 0:
    result &= c.char
    inc register.position
    c = register.chunk[register.position]
  inc register.position
  if reset: register.position = was

proc skipNum*(register: var Register) =
  while (register.chunk[register.position] and 0b1000_0000) != 0:
    inc register.position

proc skipStr*(register: var Register) =
  while register.chunk[register.position] != 0:
    inc register.position

proc deleteNum*(register: var Register) =
  var size = 0
  while (register.chunk[register.position + size] and 0b1000_0000) != 0:
    inc size
  register.chunk[].delete(register.position..<(register.position + size))

proc deleteStr*(register: var Register) =
  var size = 0
  while register.chunk[register.position] != 0:
    inc size
  register.chunk[].delete(register.position..<(register.position + size))

proc atomize*(x: string): uint32 =
  #result = 0
  #for c in x:
  #  let highorder = 0xf8000000'u32 and result
  #  result = (result shl 5) xor (highorder shr 27)
  #  result = result xor c.uint32
  #result = 0
  #for c in x:
  #  result *= 31
  #  result = result xor c.uint32
  result = x.len.uint32 and 0x0fffffff'u32
  for c in x:
    result = (result shl 4) + c.uint32
    let g = result and 0xf0000000'u32
    if g != 0:
      result = result xor (g shr 24)
      result = result and (not g)

proc randomAddr(): uint32 =
  rand(268_435_456).uint32 # 2^28, the about of bits used in atoms

var memory: Memory

proc followChunk(register: var Register, address: SomeInteger = randomAddr()) =
  if not memory.hasKey address.uint32:
    memory[address.uint32] = new Chunk
  register.chunk = memory[address.uint32]
  register.position = 0
  register.address = address.uint32

proc executeProcedure(x: string, args: seq[byte]) =
  var
    procReg = Register(chunk: memory[atomize(x)])
    varRegs = newSeq[Register](64)
    cmd = procReg.readNumber
  varRegs[0].chunk = new Chunk
  varRegs[0].chunk[] = args
  while cmd != 0: # Command 0000_0000 is jump to end, ie. halt
    let reset = (cmd and 0b0100_0000) == 0
    case (cmd and 0b0011_1000) shr 3:
    of 0b000: # Jump instructions
      case cmd and 0b0000_0111:
      of 0b001: procReg.position = procReg.readNumber
      of 0b010:
        if procReg.readString == varRegs[procReg.readNumber].readString(reset):
          procReg.position = procReg.readNumber
      of 0b011:
        if procReg.readString != varRegs[procReg.readNumber].readString(reset):
          procReg.position = procReg.readNumber
      of 0b100:
        if procReg.readNumber == varRegs[procReg.readNumber].readNumber(reset):
          procReg.position = procReg.readNumber
      of 0b101:
        if procReg.readNumber != varRegs[procReg.readNumber].readNumber(reset):
          procReg.position = procReg.readNumber
      of 0b110:
        if procReg.readNumber < varRegs[procReg.readNumber].readNumber(reset):
          procReg.position = procReg.readNumber
      of 0b111:
        if procReg.readNumber > varRegs[procReg.readNumber].readNumber(reset):
          procReg.position = procReg.readNumber
      else: discard
    of 0b001: # Copy instructions
      case cmd and 0b0000_0111:
      of 0b000:
        varRegs[procReg.readNumber].writeString(procReg.readString, reset)
      of 0b001:
        varRegs[procReg.readNumber].writeNumber(procReg.readNumber, reset)
      of 0b010:
        varRegs[procReg.readNumber].writeString(varRegs[procReg.readNumber].readString(reset), reset)
      of 0b011:
        varRegs[procReg.readNumber].writeNumber(varRegs[procReg.readNumber].readNumber(reset), reset)
      else: discard
    of 0b010: # Follow instructions
      case cmd and 0b0000_0111:
      of 0b000:
        varRegs[procReg.readNumber].followChunk(procReg.readNumber)
      of 0b001:
        varRegs[procReg.readNumber].followChunk(varRegs[procReg.readNumber].readNumber(reset))
      of 0b010:
        varRegs[procReg.readNumber].followChunk
      else: discard
    of 0b011: # Skip instructions
      case cmd and 0b0000_0111:
      of 0b000:
        varRegs[procReg.readNumber].skipStr
      of 0b001:
        varRegs[procReg.readNumber].skipNum
      else: discard
    of 0b100: # Arithmetic instructions
      case cmd and 0b0000_0111:
      of 0b000:
        varRegs[procReg.readNumber].writeNumber(varRegs[procReg.readNumber].readNumber(reset) + varRegs[procReg.readNumber].readNumber(reset), reset)
      of 0b001:
        varRegs[procReg.readNumber].writeNumber(varRegs[procReg.readNumber].readNumber(reset) - varRegs[procReg.readNumber].readNumber(reset), reset)
      of 0b010:
        varRegs[procReg.readNumber].writeNumber(varRegs[procReg.readNumber].readNumber(reset) * varRegs[procReg.readNumber].readNumber(reset), reset)
      of 0b011:
        varRegs[procReg.readNumber].writeNumber(varRegs[procReg.readNumber].readNumber(reset) div varRegs[procReg.readNumber].readNumber(reset), reset)
      else: discard
    of 0b111: # Misc instructions
      case cmd and 0b0000_0111:
      of 0b000:
        varRegs[procReg.readNumber].deleteStr
      of 0b001:
        varRegs[procReg.readNumber].deleteNum
      of 0b010:
        varRegs[procReg.readNumber].position = 0
      of 0b011:
        varRegs[procReg.readNumber].writeNumber(varRegs[procReg.readNumber].address, reset)
      else: discard
    else: discard
    cmd = procReg.readNumber

proc executeProcedureStr(x: string, arg: string) =
  executeProcedure(x, cast[seq[byte]](arg & "\0"))

var
  register: Register # = Register(chunk: chunk, position: 0)
  listRegister: Register # = Register(chunk: chunk, position: 0)

register.followChunk(atomize("add task"))
register.writeNumber 0b00_010_010 # Follow new chunk
register.writeNumber 1 # In register 1
register.writeNumber 0b01_001_010 # Copy string from register to register
register.writeNumber 1 # To register 1
register.writeNumber 0 # From register 0
register.writeNumber 0b01_001_001 # Copy int to register
register.writeNumber 1 # To register 1
register.writeNumber 0 # Literal number 0
register.writeNumber 0b01_001_001 # Copy int to register
register.writeNumber 1 # To register 1
register.writeNumber 0 # Literal number 0
register.writeNumber 0b00_010_000 # Follow given chunk
register.writeNumber 2 # In register 2
register.writeNumber atomize("task list")
register.writeNumber 0b00_111_011 # Write register address to register
register.writeNumber 2 # To register 2
register.writeNumber 1 # Address of register 1
register.writeNumber 0 # Halt, execution complete!

when false:
  register.followChunk(atomize("get tasks"))
  register.writeNumber 
  register.writeNumber 0b00_010_000 # Follow given chunk
  register.writeNumber 1 # In register 2
  register.writeNumber atomize("task list")

listRegister.followChunk(atomize("task list"))
listRegister.writeNumber 0
listRegister.position = 0
register.followChunk
register.writeString "This is the first task"
register.writeNumber 0
register.writeNumber 0
listRegister.writeNumber register.address
register.followChunk
register.writeString "This is the second task"
register.writeNumber 0
register.writeNumber 0
listRegister.writeNumber register.address

executeProcedureStr("add task", "This is the third task")

echo register.chunk[]
echo listRegister.chunk[]
listRegister.position = 0
var num = listRegister.readNumber
while num != 0:
  #echo memory[num.uint32][]
  echo num
  register.followChunk(num)
  echo register.chunk[]
  echo "Task: ", register.readString, ", status: ", register.readNumber, ", completed at: ", register.readNumber
  num = listRegister.readNumber

import strutils
var size = 0
for address, chunk in memory:
  echo "Chunk ", address.toHex, ": ", address.encodeNumber.len, " + ", chunk[].len
  size += address.encodeNumber.len
  size += chunk[].len

echo "Final size: ", size
