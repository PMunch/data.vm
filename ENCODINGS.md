# Variable length encodings
An early design decision was to base the VM around the concept of variable sized
numbers instead of fixed size ones. This was done to simplify the instruction
set required and because data typically contains a certain amount of strings
anyway there would always be the need for handling variable length fields.
Making everything variable length ensures that the VM implementation can be
simple, there will only ever be one kind of data to read, and that is the
variable size numbers.

## Challenges
There are a couple of things to take into consideration however. There are many
variable sized integer encodings, and choosing the right one can be tricky. This
document serves as a reference to the rationale of the chosen encoding. First by
listing all the considered candidates, and then by comparing them. The main
points of consideration is, in no particular order:

- Easily seekable, obviously just jumping N bytes forward won't work, but the
  encoding should be able to quite easily jump N numbers forward.
- Available bytes, at least 64 bits of data should be possible to encode.
  Potentially more, but for ease of implementation it will probably be capped at
  64 (otherwise each implementation must also contain a arbitrary size math
  implementation).
- Efficiency, there shouldn't be too much waste in detecting the encoding
- Byte aligned, again for ease of implementation, only encodings which uses
  8-bit bytes as their unit have been considered.
- Safety, some encodings offer self-synchronisation. This is a nice feature, but
  how much of an actual benefit remains to be seen.

## Encodings
Some encodings include a special mode for signed numbers, while others are only
defined for unsigned. Simply storing the raw bytes of a negative numbers in the
standard two's complement would yield poor results as it works by inverting the
number so all the high bits are 1 instead of 0 (there is more to it than this,
but that's not really relevant). This means that -1 will look like a massive
unsigned number and therefore take a lot of bytes. In order to use an encoding
which only has support for unsigned numbers we can use ZigZag encoding. This
essentially interleaves the positive and negative numbers, or more technically
store the absolute value of the number and then adds the sign bit in the least
significant bit.

### UTF-8
Since the VM should support strings of data it would be tempting to use UTF-8 to
store numbers as well. UTF-8 works by adding some control bits to the beginning
of the first character, and then some continuation bits to the rest. The first
character would have 0 as the first and only control bit if it only consists of
a single byte (to stay compliant with 7-bit ASCII). Then for two or more bytes
it consists of the number of bytes in bits along with a zero, so for two bytes
110, three bytes 1110, etc. All the bytes following the first byte starts with
the bits 10.

Properties:
- Self-synchronising, if given an address in the middle of a glyph it is
  immediately obvious if this is the start of the character or a continuation
  byte.
- Length encoded, given the first byte you know how many bytes this character
  includes. This means skipping character by character is easy.
- Not able to store more than 32-bits, and post-2003 the official spec only
  requires 21-bits so it might be hard to reuse an existing encoder.
- Self-synchronising secrifies a bit of efficiency. 32 bits requires 6 bytes.

Slices:
1 byte: 0 - 127
2 bytes: 128 - 2 047
3 bytes: 2 048 - 65 535
4 bytes: 65 536 - 2 097 151

References:
https://en.wikipedia.org/wiki/UTF-8
https://www.cl.cam.ac.uk/~mgk25/ucs/utf-8-history.txt

### LEB128/Protobuf
Quite a simple format, and can store any length number. Works by having the
first bit indicate whether or not this is the last byte in a number or not. If
the number is <128 then the number can simply be stored as is and doesn't
require any encoding.

Properties:
- Self-synchronising, only bytes starting with 0 denote the start of a new
  character.
- No length encoding, meaning that to skip a number each byte in the number must
  be read.
- Can store any length number
- Efficient, only 1 bit per byte is wasted. Storing the highest 32 bit number
  requires 5 bytes, the highest 64 bit number 10 bytes.
- Can reuse existing encoders for Protobuf/LEB128
- LEB128 has a signed version, Protobuf uses ZigZag

Slices:
1 byte: 0 - 127
2 bytes: 128 - 16 383
3 bytes: 16 384 - 2 097 151
4 bytes: 2 097 151 - 268 435 455

A slight variation on this is that the last byte in a full 9 byte encoding
doesn't require the sign bit and thus has 8 data bits instead of seven. This
sacrifices the self-synchronization property for being able to store a 64-bit
number in 9 bytes instead of ten.

References:
https://en.wikipedia.org/wiki/LEB128
https://steemit.com/technology/@teknomunk/variable-length-floating-point-numbers

### Rust varints
From the vint64 crate, this is quite a clever scheme. Designed to be able to
hold a 64 bit unsigned integer, but done in such a way that all the calculations
can be done on just a uint64. No need for a loop or heavy masking of bits. It
only requires an efficient way of getting the number of trailing and leading
zeros, both of which are typically implemented in the CPU instruction set. The
length encoding itself is akin to UTF-8, but without the continuation byte
markers, or a combination of protobufs continuation byte markers in the first
byte.

Properties:
- Length encoded, given the first byte you know how many bytes this character
  includes. This means skipping character by character is easy.
- No self-synchronization, continuation bytes are indistinguishable from start
  byte.
- Clever encoding that is both easy to implement and should be very fast
- Efficient, only 1 bit per byte is wasted with a special case for 64 bits.
  Storing the highest 32 bit number requires 5 bytes, the highest 64 bit number
  9 bytes.
- Values below 127 which are stored in a single byte still requires shifting
- Can only store 64 bit numbers

Slices:
1 byte: 0 - 127
2 bytes: 128 - 16 383
3 bytes: 16 384 - 2 097 151
4 bytes: 2 097 151 - 268 435 455

References:
https://docs.rs/vint64/latest/vint64/

### SQLite varints
Used to store variable sized numbers in SQLite databases. Works a bit different
to the first two in that instead of having a specific bit pattern it reserves
the values above 240 to encode some special handling. Some of these extracts
some extra data bits from the leading byte, but at a certain point it simply
reverts to using the first byte to store how many actual bytes the number
comprises.

Properties:
- Length encoded, given the first byte you know how many bytes this character
  includes. This means skipping character by character is easy.
- Stores 64-bit unsigned numbers
- Efficient for very low numbers, single byte can store numbers up to 240.
  Largest 32 bit number requires 5 bytes, largest 64 byte number requires 9
  bytes. Low ranges are slightly worse than protobuf though.
- Slightly trickier encoding, involves summation which might be slower than
  simple bit twidling (note: appears to need multiplication and modulus, but
  these can easily be done with bit twidling instead)
- Numbers can be sorted lexicographically as bytes
- No self-synchronization, continuation bytes are indistinguishable from start
  byte.

Slices:
1 byte: 0 - 240
2 bytes: 241 - 2 287
3 bytes: 2 288 - 67 823
4 bytes: 67 824 - 16 777 215

References:
https://sqlite.org/src4/doc/trunk/www/varint.wiki

### Dlugosz' Variable-Length Integer Encoding rev 2
Revision 1 seems to be pretty much just LEB128/Protobuf, revision 2 is closer to
SQLites scheme. Essentially there are four general forms each which encode
slightly differently. The encoding has some interesting properties in the splits
that it offers which means that the ranges are a bit uneven but allows fitting
certain commonly used data-types in fewer bytes than would otherwise be
required. Curiously this also means that there is no encoding that takes 7
bytes, but there are 4 reserved versions, one of which could be used for this.
It also supports an arbitrary length encoding where all the bits of the first
byte are 1's, that means there follows a variable integer number detailing how
many data bytes this uses. The logic here is that for numbers of that size the
"wasted" byte here doesn't matter terribly much. This also means that instead of
data buffers strings for example could just be treated as very large numbers and
would then be size-prefixed.

Properties:
- Length encoded, given the first byte you know how many bytes this character
  includes. This means skipping character by character is easy.
- Can store any length number
- Interesting value ranges, breaks are chosen more intentionally than the other
  encodings.
- No self-synchronization, continuation bytes are indistinguishable from start
  byte.
- Efficient, for certain ranges. Storing the highest 32 bit number requires 5
  bytes, the highest 64 bit number 9 bytes.

Slices:
1 byte: 0 - 127
2 bytes: 128 - 16 383
3 bytes: 16 384 - 2 097 151
4 bytes: 2 097 151 - 134 217 727
Also interesting that it has breakpoints for 128K (4 bytes), 32G (5 bytes), 1T
(6 bytes), and a GUID (17 bytes one byte less than storing two 64 bit numbers).

References:
https://web.archive.org/web/20210224160104/http://www.dlugosz.com/ZIP2/VLI.html

## So, which one is best?
As with most things in life we can't get everything we want, and these encodings
is no exception. We have three basic properties, efficiency, length encoding,
and self-synchronizing. And it seems we can only have two at a time. UTF8 has
length encoding and self-synchronization, but isn't very efficient. Protobuf has
efficiency and self-synchronization but no length encoding. And SQLite, Dlugosz'
and Rust varints has efficiency and length encoding, but no
self-synchronization. For Dlugosz' we could theoretically require each
continuation byte to include a high 1 bit, except for the last, and that way
gain self-synchronization. But it would throw off all the nice slices it is
built on and cost it efficiency. The SQLite encoding can't be given this
treatment as easily because the 1 byte case is a bit special since it stores
more than 127 values.

### So, which one is best for a data based VM?
To the best of my knowledge a VM specifically designed to be easy to implement
and embed for the sole purpose of persistant data storage has never been built
before. So the requirements of such a system is still an open question. The
SQLite encoding is enticing as it would be possible to have quite a bit larger
instruction set (the current design has all op-codes defined to fit in a single
byte). At the same time, maybe keeping the amount of instructions low is a good
thing for simplicities sake. The idea behind Dlugosz' algorithm is also very
interesting as it seems to keep commonly stored entities in mind in its design.
This is certainly something which could be kept in mind if a special algorithm
is to be designed for this purpose (chunks for example are identified by the
hash of their name, the current hashing algorithm produces hashes 28 bits long).
Self-synchronization is a feature which also seems like it would be very nice to
have, but since the current design for the VM is only addressable by chunks and
sub-chunk addressing has to be done by skipping through the records you should
never run into a case where you try to e.g. add something to the middle of a
number. This is also meant for data storage, not data transfer, so picking up a
stream mid-sending isn't much of a concern. For these reasons the choice will
likely fall on either Rust vints, SQLite, Dlugosz', or a custom algorithm. Of
course out of these SQLite is the one which is the most tried and tested, and
probably the one which has the most existing implementations to steal for anyone
wanting to implement this VM. Nim for example has a module called varint in the
standard library which seems to be the SQLite kind. That being said Rust varints
are very cleverly designed and easy to implement, it also offers the benefit of
being able to store a 28-bit chunk address in four bytes.

## Conclusion
Depending on your specific use-case each of these could be the best algorithm.
For my purposes I'm probably going to go with Rust varints, or implement
something new based on Dlugosz' ideas.
