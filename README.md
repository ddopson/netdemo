
## Problem

Design and implement a program that transfers fragments of a file to multiple remote nodes. The class should take as input:
* A file path to file of a fixed size (64MB).
* An unordered list of 64 IP addresses/port numbers.
* The maximum transfer rate for the sender (in Kbps). The rate limit describes the maximum aggregate bandwidth a sender consumes when transferring one or more fragments of the file.

The program should divide the file up into 64x1MB fragments and send one fragment to each of the 64 nodes. A TCP socket should be used for communication with each of the nodes. The transfer should honor the rate set by the user. Assume that each of the remote nodes have heterogeneous bandwidth.

#### Goals

* Minimizing the overall time it takes to send the entire 64MB file.
* Minimizing the communication overheads.
* Minimizing system resources consumed during the transfer.



## Design Discussion

#### Chunk Size

IP network communication consists of sending discrete `packets` which in most sane networks are ~1.5k each.  If we were aproaching this problem at a theoretical level, we'd send data between nodes in nice neat perfectly sized 1-packet chunks.  Unfortunately, we are working from a higher level streaming abstraction (TCP) and can only indirectly influence the packet logic.  In the end, as long and we send packets that are at least MTU/2 bytes, we will be within a factor of 2 of the optimal wire efficiency (1 full packet and 1 tiny packet).

#### API

##### Low Level Sockets API

When things are flowing smoothly, a `write` operation is non-blocking, merely scribbling the bits into an outgoing kernel buffer where they will be sent more or less as quickly as possible. (More or less because Nagle's algorithm and TCP windowing will have implications for what "as quickly as possible" means in practice).  So without a lot of work, we don't have much control over when and how fast the actual data is pushed onto the wire once queued into kernel buffers.  Our control surface must instead be the rate at which we push bits into the kernel.

Previously, I said that when things were "flowing smoothly" writes to a TCP socket are non-blocking.  Clearly, if an application writes bytes to the socket faster than they can be sent, the kernel won't be able to keep up and something must give.  Once the kernel has hit a maximum number of bytes queued up for send on a particular socket, writes to that socket WILL block.  This rudimentary mechanism of flow control works great for simple programs transfering data on a single socket, but can be dangerous for a poorly written program that intends to multiplex communication on multiple sockets.  

#### OO API

[NodeJs](http://nodejs.org/api/net.html#net_socket_write_data_encoding_callback) uses non-blocking writes and enqueues data in user mode when the kernel buffers overflow.  It provides a boolean when writing to determine when the user-mode buffer has kicked in. It also has a collback to determine when individual writes have been completed.  I believe "completed" means a TCP ack, but I haven't been able to verify this yet.  TCP and pushing bits is one of Node's strong suits.

In the [C# Socket Class](http://msdn.microsoft.com/en-us/library/system.net.sockets.socket.aspx), one could use the async [BeginSend](http://msdn.microsoft.com/en-us/library/7h44aee9.aspx) interface for sending data.  It wouldn't be very pretty, but it would work.

#### Consuming Too Many Sockets

In this example, the fan-out width is fixed at 64:1.  Opening 64 sockets in parallel is usually no big deal.  However, if the fan-out were unbounded, we would not be able to open an unbounded number of parallel TCP sockets.  First, we would hit a limit on open file descriptors for a single process.  Such could be worked around by raising the limit or by using multiple processes, but there is a practical bound on the utility of sending to so many sockets at once.  Thus we would accept an additional parameter of the maximum "width" or number of parallel TCP sessions.

Optimizing for the end-to-end transfer time now becomes tricky.  The worst case is where a single connection is vastly slower than all other connections.  The optimal behavior is to transfer at the maximum possible rate to this single slow connection using the left-over bandwidth to service the other connections while waiting for the "longest pole".  If that "longest pole" is near the end of the list, a naive implementation will suffer relatively poor performance as it won't start transfering to the "longest pole" connection until it has finished with many others.  If compensating for such cases is important, one could sample the connections initially by transferring a small portion of the overall payload.  But that solution has its own problems, not least of which is that the speed of individual connections might vary over time.  Ultimately, the best solution would depend on the use case.

## Validation

The key validation I care for is a single slow receiver.  I set up 3 fast listeners and 1 slow listener.  When the transmission starts, there is a brief interval where bytes are split evenly between the 4 connections.  Once #4's buffer fills up, the extra bandwidth is split between the first 3 connections allowing them to transmit faster while allowing the 4th connection to transmit at the maximum rate it will sustain.  Eventually the first 3 connections complete and the program waits for the 4th connection until that finishes some time later.
