import tables

var
  memory = readFile("data.vm")
  procTable: Table[string, int]

var
  lastChar = '\0'
  curIdx = 0

var
  curProc = ""

template readInt(pos): untyped =
  cast[ptr int32](memory[pos].addr)[]

template setInt(pos, dat): untyped =
  cast[ptr int32](memory[pos].addr)[] = dat

proc hob(x: int): uint =
  result = x.uint
  result = result or (result shr 1)
  result = result or (result shr 2)
  result = result or (result shr 4)
  result = result or (result shr 8)
  result = result or (result shr 16)
  result = result or (result shr 32)
  result = result - (result shr 1)

proc writeNumber*(pos: var int, val: int) =
  # TODO: change to 128-bit buffer and shift logic to avoid overflow
  var t = val * 2
  if val < 0:
    t = t xor -1
  var
    bytes = t.hob shr 7
    num = t
  memory.setLen(max(memory.len, pos + 1))
  memory[pos] = (num and 0x7f or (if bytes != 0: 0x80 else: 0)).char
  inc pos
  while bytes != 0:
    num = num shr 7
    bytes = bytes shr 7
    memory.setLen(max(memory.len, pos + 1))
    memory[pos] = (num and 0x7f or (if bytes != 0: 0x80 else: 0)).char
    inc pos

proc writeNumber*(pos: int, val: int) =
  var pos = pos
  writeNumber(pos, val)

proc writeMemory*(pos: var int, data: string) =
  memory.setLen(max(memory.len, pos + data.len))
  memory[pos..pos + data.high] = data
  pos = pos + data.len

proc writeMemory*(pos: int, data: string) =
  var pos = pos
  writeMemory(pos, data)

proc readNumber*(pos: var int): int =
  if memory.high < pos: return 0
  var
    byte = memory[pos].uint8
    i = 1
  inc pos
  result = (byte and 0x7f).int
  while (byte and 0x80) != 0:
    # TODO: Add error checking for values not fitting 64 bits
    byte = memory[pos].uint8
    inc pos
    result = result or ((byte and 0x7f).int shl (7*i))
    i += 1
  return ((result shr 1) xor (if (result and 1) == 1: -1 else: 0))

proc readNumber*(pos: int): int =
  var pos = pos
  readNumber(pos)

proc readAddress*(pos: var int): int =
  pos + readNumber(pos) - 1

proc readAddress*(pos: int): int =
  var pos = pos
  readAddress(pos)

proc writeStr*(pos: var int, str: string) =
  writeMemory(pos, str & "\0")

proc writeStr*(pos: int, str: string) =
  var pos = pos
  writeStr(pos, str)

proc readStr*(pos: var int): string =
  if memory.high < pos: return ""
  var
    c = memory[pos]
  while c != '\0':
    result &= c
    inc pos
    if memory.high < pos: return
    c = memory[pos]
  inc pos

proc readStr*(pos: int): string =
  var pos = pos
  readStr(pos)

proc skipNull*(pos: var int) =
  if pos > memory.high: return
  while memory[pos] == '\0':
    inc pos
    if pos >= memory.high: return

#memory = "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
memory = ""
writeNumber(0, 42)
echo cast[seq[uint8]](memory)
echo readNumber(0)
memory = "hello_world\0"
var pos = memory.len
#memory.setLen(100)
writeNumber(pos, 30)
echo cast[seq[uint8]](memory)
writeStr(pos,  "\0\1\2\3\4\5\6\7\8\9")
echo cast[seq[uint8]](memory)
writeStr(pos - 10, "ab")
echo cast[seq[uint8]](memory)

template printMem =
  echo cast[seq[uint8]](memory)

memory = ""
pos = 0
writeNumber(pos, 2)
writeStr(pos, "hello_world")
writeNumber(pos, 0)
writeStr(pos, "\0\0\0\0\0")
writeStr(pos, "second_proc")
writeNumber(pos, 100)
printMem()
pos = 0

var
  procsToRead = readNumber(pos)
while procsToRead > 0:
  procTable[readStr(pos)] = readAddress(pos)
  skipNull(pos)
  dec procsToRead

echo procTable

proc runProc(p: string): string =
  var pos = procTable[p]
  while true:
    case memory[pos]:
    of '\0':
      break
    of '\1':
      inc pos
      let
        a = readAddress(pos)
        d = readNumber(pos)
      writeNumber(a, d)
    else: discard
    inc pos

echo run_proc("hello_world")

while false:
  while memory[curIdx] != lastChar or lastChar != '\0':
    echo curIdx, ": ", curProc
    if memory[curIdx] == '\0' and curProc.len != 0:
      procTable[curProc] = readInt(curIdx + 1)
      curProc = ""
      curIdx += 4
    else:
      curProc &= memory[curIdx]
    lastChar = memory[curIdx]
    inc curIdx

  echo procTable
  echo memory.len

  proc runProc(p: string): string =
    var pos = procTable[p]
    while true:
      case memory[pos]:
      of '\0':
        break
      of '\1':
        let
          a = readInt(pos + 1)
          d = readInt(pos + 5)
        setInt(a, d)
      else: discard
      inc pos

  echo run_proc("hello_world")
  echo memory
