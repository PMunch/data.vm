# Data.VM
This is an experiment!

More specifically it's an experiment into creating a data format which is
inherently linked to the reading and manipulation of the data. The goal was to
design a VM which was easier to implement than trying to extract the data
without writing the VM. The reason was to have a way to share data between
independently implemented applications while guaranteeing that no implementation
could skip or change the rules on how to change the data. The motivating example
was a task manager which has rules on how tasks interact with each other and on
how tasks are set to a completed state. It would also allow one application to
add "hooks" into the data which the other clients would follow even without
knowing that hooks where present.

The VM only needs to be implemented once, then it can be re-used for different
data formats. The formats could each have their own logic on how to read and
write data, and the author of the format could easily add new rules for how data
is handled without any participating applications having to be made aware of the
changes. The reason it's implemented as a VM and not as a data format with hooks
support is that it's almost impossible to partially implement the VM and get
correct results. It would be much easier to just implement parts of a data
format, something which is commonly seen in the wild.

There are an additional three working documents I wrote while working on this
project which can be found in this repository. They where partially meant to
work as an implementation guide, and partially to document things for myself as
I went along.

- DESIGN.md, gives information on how the VM is designed, and a bit more of the
rational behind why it is made
- INSTRUCTIONS.md, lists the instruction set and how to parse instructions
- ENCODINGS.md, lists the various formats of variable sized integers considered
for the base format for this project, the design criteria for choosing one of
them, and the rationale behind chosing the one I did.
