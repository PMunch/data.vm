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
- Every address is relative
- Every string is null terminated

### Procedure table
The file starts with a list of strings and addresses on the format:
```
<count>procedure1\0<address><padding>procedure2\0<address>
```
That is the count of procedures in the table, followed by the zero-terminated
name of the procedure, and then the address of the procedure relative to where
the address is written. Then after an arbitrary amount of padding bytes (all
zeros) the next procedure label. The reason for the padding is that since the
addresses are variable size integers if the format wants to support swapping out
the declaration of a procedure the number would need to be able to grow without
having to rewrite all the preceding entries.

### Numbers
All numbers (and by extension addresses) are stored as signed variable length
numbers according to the Protobuf Zig-Zag encoding.
