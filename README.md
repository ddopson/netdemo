
=== Design Discussion

All IP network communication is mediated by a discrete series of `packets` which in most sane networks is ~1.5k.  If we were aproaching this problem at a theoretical level, we'd send data between nodes in nice neat 1-packet chunks.  Unfortunately, that is not the TCP abstraction provided by the operating system.  While we could implement a solution using UDP, or even with raw IP packets (where available), this would greatly expand the scope and cost of the project and necesitate reimplementing the acknowledge/retransmit logic to be had for free using TCP.  Additionally, TCP allows us to operate in some environments where a subset of the machines must cross a firewall that is configured to only allow outbound TCP session initation, or a firewall that restricts access all but a few TCP ports.  While theoretically, modifying a firewall is "easy" from a technical level, organizational challenges predominate.

[TCP](http://en.wikipedia.org/wiki/Transmission_Control_Protocol) is implemented with kernel support and typically a dash of hardware acceleration.  So unless we want to write kernel level drivers, we are limited to the interfaces provided by the operating system.  Once a TCP session is established, the kernel provides the ability to queue up buffers of data to be sent. Some fancier interfaces allow for so called "zero-copy" transmission, but this is merely an optimization and for our purposes we can ignore that feature.  When things are flowing smoothly, a `write` operation is non-blocking, merely scribbling the bits into an outgoing kernel buffer where they will be sent more or less as quickly as possible. (More or less because Nagle's algorithm and TCP windowing will have implications for what "as quickly as possible" means in practice).  So without a lot of work, we don't have much control over when and how fast the actual data is pushed onto the wire once queued into kernel buffers.  Our control surface must instead be the rate at which we push bits into the kernel.

Previously, I said that when things were "flowing smoothly" writes to a TCP socket are non-blocking.  Clearly, if an application writes bytes to the socket faster than they can be sent, the kernel won't be able to keep up and something must give.  Once the kernel has hit a maximum number of bytes queued up for send on a particular socket, writes to that socket WILL block.  This rudimentary mechanism of flow control works great for simple programs transfering data on a single socket, but can be dangerous for a poorly written program that intends to multiplex communication on multiple sockets.  Several solutions to this issue present themselves: 1) we could utilize a single thread per connection, though this is a pretty heavyweight solution, 2) we could take great care to never overfill the kernel buffer and block, or 3) we could utilize a dirt simple design such as round-robining packets between sockets which accepts blocking writes, trading performance for robustness and simplicity of implementation (we took an analogous path when implementing parallel memcache operations in PHP at Zynga; it was fast enough).  [NodeJs](http://nodejs.org/api/net.html#net_socket_write_data_encoding_callback) uses non-blocking writes and enqueues data in user mode when the kernel buffers overflow.  It provides a boolean when writing to determine when the user-mode buffer has kicked in.

In the [C# Socket Class](http://msdn.microsoft.com/en-us/library/system.net.sockets.socket.aspx), one could use the async [BeginSend](http://msdn.microsoft.com/en-us/library/7h44aee9.aspx) interface for sending data without fear of blocking.  To be honest though, async coding in C# is pretty verbose and clunky compared to Node, so where possible, I prefer worker/queue patterns in that environment.  

#### Consuming Too Many Sockets

In this example, the fan-out width is fixed at 64:1.  Opening 64 sockets in parallel is usually no big deal.  However, if the fan-out were unbounded, we would not be able to open an unbounded number of parallel TCP sockets.  First, we would hit a limit on open file descriptors for a single process.  Such could be worked around by raising the limit or by using multiple processes, but there is a practical bound on the utility of sending to so many sockets at once.  Thus we would accept an additional parameter of the maximum "width" or number of parallel TCP sessions.

Optimizing for the end-to-end transfer time now becomes tricky.  The worst case is where a single connection is vastly slower than all other connections.  The optimal behavior is to transfer at the maximum possible rate to this single slow connection using the left-over bandwidth to service the other connections while waiting for the "longest pole".  If that "longest pole" is near the end of the list, a naive implementation will suffer relatively poor performance as it won't start transfering to the "longest pole" connection until it has finished with many others.  If compensating for such cases is important, one could sample the connections initially by transferring a small portion of the overall payload.  But that solution has its own problems, not least of which is that the speed of individual connections might vary over time.  Ultimately, a good solution would be crafted to the real-world characteristics of the network.

#### Blah

A further limit on top of the interface exposed by the kernel will be the interface exposed by the language or library chosen.  I don't have C# installed, nor a Windows box at hand (and I don't yet trust Mono), so I'm going to go with either Ruby (a bit more mature) or Nodejs (elegant event loop for parallel work).  Let's see what we have available.

For each socket, the kernel has a maximum buffer size of bytes that it will queue up unsent.  Once this buffer
When the underlying network is slower than the rate at which bytes are enqueued for sending, 

Let's take note of a few key features:
* Buffer Size
* Enable/Disable Nagle's algorithm

=== Pragmatic Solutions

The crazy-insane-powerful GNU [parallel](http://www.gnu.org/software/parallel/) utility could solve this entire problem with a single line:

  

Apeing parallel, one could establish 64 pseudo-SCP sessions (SSH sessions that run `tee file.txt`, copying stdin to disk) that listen to 64 named pipes, and round robin between those named pipes echoing chunks of data. 

