#!/usr/bin/env coffee

Net = require 'net'
Commander = require 'commander'

class Sender
  constructor: (@port) ->
    socket = Net.connect port, 'localhost',  ->


for port in [7000...7004]
  new Sender(port)


