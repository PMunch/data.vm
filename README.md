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
