# Data.VM
This is a very simple to implement VM which primary goal is the consistent
storage of data. Instead of storing data in a plainly readable format and then
have rules for interacting with said data as a separate concept this merges data
with the modification of said data. As an example let's look at a very simple
TODO list application. Tasks are stored with their title, their state (done,
not done), and the time of completion. Now in a plain data format these three
items are simply stored as fields, and there exists a rule that when marking a
task as done the completion time field should be populated. This is all well and
good for our simple application. But if someone else wanted to write a mobile
client for this format we would run into trouble. If the mobile developer didn't
implement the rule that the done field should be set when a task is done it
might break our application. But maybe they implement the only rule we had in
place and everything was fine. Now consider that we add a new state along with
done and not done called blocking along with a field of which task this task is
blocked by. If we simply add this into our application the mobile application
might break because there are now unexpected fields. And we've just added a new
rule, namely that tasks that depend on another task should go from blocked to
not done as soon as the dependent task is marked as done. This is another rule
that the author of the mobile application have to implement, otherwise we can
run into further data conflicts.

As you can imagine this scenario happens quite often as data is exchanged
between applications. It makes the experience of our applications segmented, and
it causes headache when we want to add features or automatic transitions to our
data formats. This is the problem that data.vm tries to solve. Instead of storing
data as a simple data format with external rules we store both data and rules in
the same format. In order to read data out of the file you call a function to
read data, and in order to change it you call procedures to change things. The
specific list of available procedures depends entirely on the format. In order to
make every client support every feature of the format the VM required to run this
is designed to be as simple yet flexible as absolutely possible. And the VM
itself can be implemented completely independent of the specific format.

## Basic design
- Every number is encoded as a variable length number
- Every string is null terminated
- Addressing is done based on "atoms"

### Addressing
The top level of the file format is split into addressable chunks. Each chunk
has it's size in bytes and the address for that chunk on it. Chunk addresses are
atoms, a simple hash of its identifier. For example the procedure `hello_world`
would be stored into the file as:

```
<hash of "hello_world"><size of chunk data><data in chunk>
```

When the address of an atom is looked up, it returns the position for the 0-th
byte in the chunk data. From there it is possible to traverse or execute the
data within the chunk. The reader of the data should not attempt to read the
data stored in chunks. To execute the `hello_world` procedure, simply look up
the chunk with the `hello_world` atom address and start executing the
instructions in the chunk.

### Numbers
All numbers (and by extension atoms) are stored as signed variable length
numbers according to the Protobuf Zig-Zag encoding. That is 0 is stored as 0, -1
is stored as 1, 1 is stored as 2, etc. The bottom seven bits are data, and the
highest bit is used for whether or not it's the final byte in the number. (Maybe
have both signed and unsigned numbers? Especially if strings are implemented
using these as one byte now only stores -63..64 so only half the range will ever
be used. Same for atoms. Also, how to deal with floating point? Maybe two signed
numbers, base and power of ten)

### Strings
Strings are stored as null-terminated UTF-8 strings.
(Store strings as variable length numbers? UTF codepoints instead of
UTF-8 as numbers? Remove string handling from the VM and introduce memory
copying instructions instead? Pro: can deal with strings, cons: have to have
some way of specifying sizes and such?)

## Implementing the VM

Once the procedures to create hashes and parse numbers and strings then the
actual execution of programs can be done. The VM needs a couple simple things to
function, namely a table of chunks to do look ups in, an execution pointer, and
a some data element pointers. The execution pointer is simply a chunk and the
current position within the chunk, this is to decide what to execute next. The
data element pointers are numbered 0 through 127 and will appear in various
operations. Then are essentially the same as the execution pointer, simply a
pair of chunk and position in the chunk. The execution pointer is henceforth
known as EP and the data element pointers are referred to as registers.

### Execution
To execute a procedure simply calculate its atom hash, set the EP to the chunk
and its first element. If the procedure takes arguments they should be stored in
an arbitrary chunk and the first register (register 0, or R0 for short) should
point to the first byte in this chunk. Note that these arbitrary data chunks
don't actually have to live with the rest of the chunks and as they shouldn't be
written to the file it might be easier to store them elsewhere. Now everything
is ready to start executing. The core execution loop is essentially just reading
a variable size number from EP, then determining what to do based on that
number, and lastly advance EP to the next instruction. Since the VM is designed
to be easy to implement the set of instructions is pretty small. They are split
into five categories and all the instructions have some common traits. All
instructions fit into a single byte of a variably sized number. The first bit of
this byte is used by the variable number implementation, so the instruction is
only the last 7 bits. The first of these seven bits is the advance flag.
Instructions that read or write registers should not advance the address after
reading or writing if this flag is set to 0. Instructions that don't read or
write from registers must leave this bit as 0. The next three bits are the
category of instruction. The categories are in order jump instructions,
copy instructions, follow instructions, skip instructions, arithmetic
instructions, and misc instructions.
