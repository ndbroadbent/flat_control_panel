#!/usr/bin/env ruby

def relative(filename)
  File.join(File.dirname(__FILE__), filename)
end

require 'rubygems'
require relative('octopus')
require 'yaml'

require 'net/http'
require 'uri'

config = YAML.load_file relative("config.yml")
base_url = URI.parse(config['sinatra_base_url'])

while true
  begin
    # Loop until all devices are connected
    o_connect = false

    while not o_connect
      begin
        @octopus = Octopus.new config["octopus_devnode"], 9600, 14
        @octopus.reset    # Tries to send reset string to octopus reader. Raises error if not connected.
        o_connect = true
      rescue
        puts "Waiting for octopus card reader to be available..."
        sleep 2
      end
    end

    while true
      id = @octopus.read

      # After a tag is read, send it to the sinatra server for validation and processing.
      # Response doesnt matter.
      res = Net::HTTP.start(base_url.host, base_url.port) {|http|
        http.get("/octopus/#{id}")
      }

    end
  rescue
    puts "Octopus was disconnected. Looping until connected again."
  end
end

