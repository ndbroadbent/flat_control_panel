#!/usr/bin/env ruby

def relative(filename)
  File.join(File.dirname(__FILE__), filename)
end

require 'rubygems'
require 'yaml'

require 'net/http'
require 'uri'
require 'rexml/document'


config = YAML.load_file relative("config.yml")
base_url = URI.parse(config['sinatra_base_url'])

weather_xoap_url = "http://xoap.weather.com/weather/local/#{config["weather_station"]}?dayf=1&link=xoap&prod=xoap&par=#{config["weather_partner_id"]}&key=#{config["weather_license_key"]}"

# Evo T20 is synced to UTC. HK time is UTC +8
def hk_time
  Time.now + 8*60*60
end

while true
  begin
    # get the XML data as a string
    xml_data = Net::HTTP.get_response(URI.parse(weather_xoap_url)).body

    # Parse the XML, return a hash containing day ppcp and night ppcp (precipitation probability)
    doc = REXML::Document.new(xml_data)
    ppcp_hash = {}
    doc.elements.each('//dayf/day/part') do |el|
      ppcp_hash[el.attributes['p']] = el.elements["ppcp"].text
    end

    # If the time is after 7pm, use the night ppcp.
    # Else, use the day ppcp.
    ppcp = hk_time.hour >= 19 ? ppcp_hash["n"] : ppcp_hash["d"]

    res = Net::HTTP.start(base_url.host, base_url.port) do |http|
      # If there is a chance of rain (ppcp > ppcp_threshold), turn on the umbrella bucket lights.
      if ppcp.to_i > config["ppcp_threshold"].to_i
        http.get("/umbrella_bucket/on")
      # If not, turn it off.
      else
        http.get("/umbrella_bucket/off")
      end
    end

    # Recheck weather every 4 hours.
    sleep(60*60*4)
  rescue
    puts "Something went wrong. Rechecking weather."
  end
end

