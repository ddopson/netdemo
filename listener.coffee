#!/usr/bin/env coffee

Net = require 'net'


class Receiver
  constructor: (@port, @rate) ->
    @total_received = 0

    @listener = Net.createServer (socket) =>
      socket.on 'data', (data) => @dataReceived(data)
  
    @listener.listen(@port)

  dataReceived: (data) ->
    @total_received += data.length


receivers =
for port in [7000...7004]
  new Receiver(port, 0)

  
setInterval ->
  txt = (r.total_received for r in receivers).join(', ')
  console.log "Received: #{txt}"
, 500
  
