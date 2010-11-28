#!/usr/bin/env ruby

def relative(filename)
  File.join(File.dirname(__FILE__), filename)
end

require 'rubygems'
require 'rubyk8055'
require relative('dsp420.rb')
include USB

require 'sinatra'
require 'yaml'
require 'net/http'
require 'uri'

# Load $config.
$config = YAML.load_file(relative("config.yml"))
$users = YAML.load_file(relative("authorized_users.yml"))

SwitchChannel = $config["SwitchChannel"]
SwitchDelay = $config["SwitchDelay"]
MsgDelay = $config["MsgDelay"]

$k8055 = RubyK8055.new
$k8055.connect
$k8055.clear_all_digital

$lastOctopusID = ""

def lcd_message(str, s_pos=21, e_pos=40, timeout=true)
  $dsp420.write str, s_pos, e_pos
  if timeout
    sleep MsgDelay
    lcd_default
  end
end

def lcd_default   # Default lcd display
  lcd_message " ==== Flat 10C ==== ", 1, 20, false
  lcd_message " Octopus / Internet ", 21, 40, false
end

def unlock_door
  $k8055.set_digital SwitchChannel, false
  # Clears the channel after delay.
  sleep SwitchDelay
  $k8055.set_digital SwitchChannel, false
end

def user_select_options
  $users.map {|name, params| "<option value=\"#{name}\">#{name}</option>" }.join
end

# Evo T20 is synced to UTC. HK time is UTC +8
def hk_time
  Time.now + 8*60*60
end

def hk_time_fmt
  hk_time.strftime("%Y-%m-%d %H:%M:%S")
end

def shellfm_trigger(name)
  # Send a trigger to shell-fm server if user has any configured radio preferences.
  # (and if the time is reasonable.)
  time = hk_time
  if time.hour >= 7 and time.hour <= 22
    if radio_prefs = YAML.load_file(relative("user_radio_prefs.yml"))
      if stations = radio_prefs[name]
        # Pick a random station, and play it.
        station = stations[rand(stations.size)]
        base_url = URI.parse("http://music-10c/")
        begin
          res = Net::HTTP.start(base_url.host, base_url.port) {|http|
            http.read_timeout = 60
            http.get("/play_station_if_idle?station=#{station}")
          }
        rescue
          # Request timed out after 60 seconds.
        end
      end
    end
  end
end

# Loop until devices are connected
l_connect = false

while not l_connect
  begin
    $dsp420 = DSP420.new $config["lcd_devnode"]
    l_connect = true
  rescue
    puts "No LCD connected."
    sleep 2
  end
end

lcd_default


get '/' do
  erb :index
end

get '/octopus/:id' do
  # If user can authenticate
  if user = $users.detect {|u| u[1]["octopus_id"] == params[:id] }
    name = user[0]
    unlock_door
    message = "  [#{params[:id]}]  " +
              "Welcome, #{name.split.first}!"
    lcd_message message, 1, 40, true
    shellfm_trigger(name)
  else
    message = "  [#{params[:id]}]  " +
              "  Access Denied."
    lcd_message message, 1, 40, true
  end
  return ""
end

post '/unlock' do
  # If user can authenticate
  user = $users[params[:user]]
  if user && user['http_pwd'] && user['http_pwd'] == params[:password]
    unlock_door
    name = params[:user]

    lcd_message "  HTTP - #{ @env['REMOTE_ADDR'] } ", 1, 20, false
    message = "Welcome, #{name.split.first}!"
    lcd_message message, 21, 40, true
  else
    lcd_message "  HTTP - #{ @env['REMOTE_ADDR'] } ", 1, 20, false
    message = "  Access Denied."
    lcd_message message, 21, 40, true
  end

  return "<html><body><p>HTTP - #{ @env['REMOTE_ADDR'] }</p><h2>#{message}</h2></body></html>"

end

# To manually update time.
get '/gettime' do
  `sudo /usr/bin/getTime.sh &`
  return ""
end


# Shows a simple form to edit the alarms.yml file for the shellfm_lcd_console
get '/edit_users' do
  @filename = File.join(File.dirname(__FILE__), "authorized_users.yml")
  @data = File.open(@filename, "r").read

  erb :edit_users
end
post '/edit_users' do
  @filename = File.join(File.dirname(__FILE__), "authorized_users.yml")
  user = $users[params[:user]]
  if user && user['http_pwd'] && user['http_pwd'] == params[:password]
    File.open(@filename, "w") do |f|
      f.puts params['data']
    end
    $users = YAML.load(params['data'])
    redirect '/'
  else
    return "<html><body><h2>YOU SHALL NOT PASS</h2></body></html>"
  end
end

