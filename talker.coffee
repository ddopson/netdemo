#!/usr/bin/env coffee

Net = require 'net'
File = require 'fs'
Program = require 'commander'
PQueue = require 'pqueue'

ONE_MEG    = 1024*1024
CHUNK_SIZE = 1500
MAX_TOKENS = 20 # burst up to 20k before throttling
MAX_PENDING = 20

Throttle = new class Throttle
  constructor: ->
    @tokens = 0
    @last_t = Date.now()
    @waiters = new PQueue
      priority: (item) -> item[0]
 
  configure: (kbps) ->
    @kbps = kbps

  waitFor: (n, cb) ->
    @waiters.push [-n, cb]
    @timer() unless @scheduled
  timer: ->
    @scheduled = false
    now = Date.now()
    toks = (now - @last_t)*@kbps / 1000
    @tokens += (now - @last_t) * @kbps / 1000
    @last_t = now
    @tokens = Math.min(@tokens, MAX_TOKENS)
    cb = null
    if @tokens > 1
      @tokens -= (CHUNK_SIZE / 1024)
      [n, cb] = @waiters.pop()
    if @waiters.length > 0
      ms = 1000 * (1 - @tokens) / @kbps
      setTimeout (=> @timer()), ms
      @scheduled = true
    cb?()




class Sender
  constructor: (@host, @port, @data) ->
    @socket = Net.connect @port, @host, => @trySend()
    @socket.on 'drain', => @trySend()
    @pending = @sent = 0

  state: ->
    return 'T' if @waiting
    return 'F' if @doneSending
    return 'D' if @done
    return 'B'

  trySend: ->
    return if @waiting
    @waiting = true
    Throttle.waitFor @sent, =>
      @waiting = false
      chunk = @data.next()
      if chunk == null
        @socket.end()
        @doneSending = true
        return
      @pending++
      @sent++
      written = @socket.write chunk, =>
        @pending--
        if @doneSending && @pending == 0
          @done = true
      @trySend() if written
      

class DataMem
  # A 'better' implementation would be to stream data from disk if we want to handle large files
  constructor: (@buffer) ->
    @offset = 0

  next: ->
    return null if @offset >= @buffer.length
    chunk = @buffer.slice(@offset, Math.min(@offset+CHUNK_SIZE, @buffer.length))
    @offset += CHUNK_SIZE
    return chunk


Program.parse(process.argv)

[file, remotes, throttle] = Program.args

console.log file, remotes, throttle

data = File.readFileSync(file)

Throttle.configure(throttle)

slices =
  for i in [0...data.length/ONE_MEG]
    start = ONE_MEG*i
    end = Math.min(ONE_MEG*(i+1), data.length)
    # note that Buffer slicing is a no-copy operation in node, just pointer arithmetic
    new DataMem(data.slice(start, end))

senders =
  for remote in remotes.split(',')
    [host, port] = remote.split(':')
    if typeof port == 'undefined'
      [host, port] = ['localhost', host]
    new Sender(host, port, slices.shift())

interval = setInterval ->
  #txt = (s.socket.bufferSize for s in senders).join(', ')
  txt = (s.state() for s in senders).join(', ')
  done = 0
  for s in senders
    done++ if s.done
  if done == senders.length
    clearInterval interval
  console.log "Pending: #{txt}  #{Throttle.waiters.length}"
, 500
  

