Seven bits total, fits in a single byte using variable length encoding
Three bits, instruction type
Four bits, instruction subtype
Arguments are listed alphabetically, A, B, C, etc.
Arguments are always a registry to read that kind of data from. This should be
read as a signed value, the register being the absolute value of the number read,
if the value is negative the register should not be advanced.
000
JUMP
---000
Jump to end, ie. end of procedure (Maybe have this for data chunks as well?)
---001
Jump unconditonally to A at position B (B should almost always be zero or a value from misc command 011)
---010
Jump if equal, compares int A to int in register B, jump to C if equal
---011
Jump if not equal, compares int A to int in register B, jump to C if not equal
---100
Jump if less than, compares int A to int in register B, jump to C if less than
---101
Jump if more than, compares int A to int in register B, jump to C if more than
---110
Jump if less than, compares float A to float in register B, jump to C if less than
---111
Jump if more than, compares float A to float in register B, jump to C if more than
001
COPY (If a copy is done into a register which is not at the end of the chunk then data is inserted not overwritten)
---000
Copy int from register B to register A
---001
Copy C ints from register B to register A
---010
Copy ints from register B to register A until a zero value is found (not a zero byte)
010
FOLLOW
---000
Set up register A to follow address B
---001
Set up register A to follow address read from register B
---010
Set up register A to follow new chunk (with random address)
011
SKIP (Maybe make part of copy? Copy to void instructions)
---000
Skip int in register A
---001
Skip B ints in register A
---010
Skip ints in register A until a zero value is found (not a zero byte)
100
ARITHMETIC 1
---000
Add unsigned number in register B with register C and stores the result in A
---001
Subtract
---010
Multiply
---011
Divide
---100
Add signed number in register B with register C and stores the result in A
---101
Subtract
---110
Multiply
---111
Divide
111
MISC?
---000
Deletes int in register A
---001
Deletes B ints in register A
---010
Deletes ints in register A until a zero value is found
---011
Reset counter for register A? (No different from following it again, but might be practical if the original address is hard to get)
---100
Writes address of chunk followed by register B into register A (Maybe this could be used instead of reset counter? Get the address and then follow it again)
---101
Writes byte position of register B into register A
