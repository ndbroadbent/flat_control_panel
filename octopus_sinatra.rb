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
GreenChannel = $config["GreenChannel"]
AlarmChannel = $config["AlarmChannel"]
HallLightChannel = $config["HallLightChannel"]

$hall_light_on = false
$hall_light_thread = nil

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

def unlock_door_action
  Thread.new do
    $k8055.set_digital SwitchChannel, false
    $k8055.set_digital GreenChannel, false
    # Clears the channel after delay.
    sleep SwitchDelay
    $k8055.set_digital SwitchChannel, false
    sleep 1.5
    $k8055.set_digital GreenChannel, false
  end
end

def access_denied_action
  Thread.new do
    $k8055.set_digital AlarmChannel, false
    # Flash buzzer on and off 5 times
    9.times do
      sleep 0.2
      $k8055.set_digital AlarmChannel, false
    end
  end
end

def hall_light_timed_action(on_time)
  return Thread.new do
    $k8055.set_digital HallLightChannel, false
    $hall_light_on = true
    sleep (on_time) # Sleep for x seconds, then turn off light.
    $k8055.set_digital HallLightChannel, false
    $hall_light_on = false
  end
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
        successful = false
        while !successful
          begin
            res = Net::HTTP.start(base_url.host, base_url.port) {|http|
              http.get("/play_station_if_idle?station=#{station}")
            }
            successful = true
          rescue
            # Request timed out, try again.
          end
        end
      end
    end
  end
end

def hall_light_trigger
  # If its past 10pm, and before 8am, turn on the hall light for 15 minutes.
  time = hk_time
  if time.hour >= 22 or time.hour <= 8
    $hall_light_thread = hall_light_timed_action(60 * 15)
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
    unlock_door_action
    message = "  [#{params[:id]}]  " +
              "Welcome, #{name.split.first}!"
    lcd_message message, 1, 40, true

    # Post unlock actions
    # ------------------------------------------
    shellfm_trigger(name)
    hall_light_trigger
  else
    access_denied_action
    $lastOctopusID = params[:id]
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
    name = params[:user]
    unlock_door_action
    lcd_message "  HTTP - #{ @env['REMOTE_ADDR'] } ", 1, 20, false
    message = "Welcome, #{name.split.first}!"
    lcd_message message, 21, 40, true

    # Post unlock actions
    # ------------------------------------------
    shellfm_trigger(name)
    hall_light_trigger
  else
    access_denied_action
    lcd_message "  HTTP - #{ @env['REMOTE_ADDR'] } ", 1, 20, false
    message = "  Access Denied."
    lcd_message message, 21, 40, true
  end

  return "<html><body><p>HTTP - #{ @env['REMOTE_ADDR'] }</p><h2>#{message}</h2></body></html>"

end

post '/hall_light' do
  # If user can authenticate
  user = $users[params[:user]]

  message = "Nothing Changed."
  if user && user['http_pwd'] && user['http_pwd'] == params[:password]
    # Kill hall light timed thread, if running
    $hall_light_thread.kill if $hall_light_thread
    $hall_light_thread = nil

    if params[:hall_light] = "ON"
      unless $hall_light_on
        $k8055.set_digital HallLightChannel, false
        $hall_light_on = true
        message = "Hall light is now on."
      end
    else
      if $hall_light_on
        $k8055.set_digital HallLightChannel, false
        $hall_light_on = false
        message = "Hall light is now off."
      end
    end
  else
    message = "Access Denied."
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

