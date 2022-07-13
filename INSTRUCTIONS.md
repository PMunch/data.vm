Seven bits total, fits in a single byte using variable length encoding
First bit, advance register 1=yes, 0=no. Since all numbers are signed, replacement codes can be seen as negative
Three bits, instruction type
Three bits, instruction subtype
Arguments are listed alphabetically, A, B, C, etc.
000
JUMP
---000
Jump to end, ie. end of procedure
---001
Jump unconditonally to A
---010
Jump if equal, compares string A to string in register B, jumps to C if equal
---011
Jump if not equal, compares string A to string in register B, jumps to C if not equal
---100
Jump if equal, compares int A to int in register B, jump to C if equal
---101
Jump if not equal, compares int A to int in register B, jump to C if not equal
---110
Jump if less than, compares int A to int in register B, jump to C if less than
---111
Jump if more than, compares int A to int in register B, jump to C if more than
001
COPY (Maybe drop replacing instructions, have to use delete then insert instead)
---000
Copy raw string B to register A, no replacement
---001
Copy raw int B to register A, no replacement
---010
Copy string from register B to register A, no replacement
---011
Copy int from register B to register A, no replacement
---100
Copy raw string to register, replacing a string
---101
Copy raw int to register, replacing an int
---110
Copy string from register A to register B, replacing a string
---111
Copy int from register A to register B, replacing an int
010
FOLLOW
---0000
Set up register A to follow address B
---0001
Set up register A to follow address read from register B
---0010
Set up register A to follow new chunk
011
SKIP (Maybe make part of copy? Copy to void instructions)
---000
Skip string in register A
---001
Skip int in register A
100
ARITHMETIC 1
---000
Add number in register B with register C and stores the result in A
---001
Subtract
---010
Multiply
---011
Divide
111
MISC?
---000
Deletes string in register A
---001
Deletes int in register A
---010
Reset counter for register A? (No different from following it again, but might be practical if the original address is hard to get)
---011
Writes address of chunk followed by register B into register A (Maybe this could be used instead of reset counter? Get the address and then follow it again)
