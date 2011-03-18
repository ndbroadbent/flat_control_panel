#!/usr/bin/ruby
# Simple DSP-420 LCD Ruby Class.

require 'rubygems'
require 'serialport'
require 'socket'

class DSP420
  def initialize(port = "/dev/ttyUSB1")
    @sp = SerialPort.new port, 9600
    @sp.flow_control = SerialPort::NONE
  end

  def hexctl(i)
    # converts an integer between 1 and 40 to its hex control character.
    "0x#{(i + 48).to_s(16)}".hex.chr
  end

  def clear(start_pos=1, end_pos=40)
    # Clears (C) all characters from start_pos to end_pos
    @sp.write 0x04.chr + 0x01.chr +
              "C" + hexctl(start_pos) + hexctl(end_pos) + 0x17.chr
  end

  def set_cursor(pos)
    # Sets cursor pos (P) to position 'pos' (between 1 and 40)
    @sp.write 0x04.chr + 0x01.chr + "P" + hexctl(pos) + 0x17.chr
  end

  def write(string, min = 1, max = 40, pre_clear = true)
    string = string[0, (max-min+1)]
    # Writes string to LCD.
    # The pre_clear var is a hack to fix a timing bug due to setting the cursor and then
    # writing data. It fixed the time not being displayed properly.
    clear(min, max) if pre_clear
    set_cursor(min)
    sleep 0.1 unless pre_clear
    @sp.write string
  end

  def center(str, length)
    # if a string is less than the max length, it pads spaces at the left to center it.
    if str.size < length
      lpad = ((length - str.size) / 2).to_i
      return " " * lpad + str
    end
    str
  end

  def format_time(t)
    min, sec = (t.to_i / 60), (t.to_i % 60)
    min, sec = 0, 0 if min < 0
    time = "%02d:%02d" % [min, sec]
  end
end

