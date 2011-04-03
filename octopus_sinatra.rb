#!/usr/bin/env ruby

def relative(filename)
  File.join(File.dirname(__FILE__), filename)
end

require 'rubygems'
require 'rubyk8055'
require relative('dsp420')
include USB
require relative('xbmc')
include XBMC

require 'sinatra'
require 'yaml'
require 'net/http'
require 'uri'

# Load $config.
$config = YAML.load_file(relative("config/config.yml"))
$users = YAML.load_file(relative("config/authorized_users.yml"))

SwitchChannel = $config["SwitchChannel"]
GreenChannel = $config["GreenChannel"]
AlarmChannel = $config["AlarmChannel"]
HallLightChannel = $config["HallLightChannel"]
FanChannel = $config["FanChannel"]
UmbrellaChannel = $config["UmbrellaChannel"]

$hall_light_on, $fan_on, $umbrella_on = false, false, false
$hall_light_thread = nil

SwitchDelay = $config["SwitchDelay"]
MsgDelay = $config["MsgDelay"]

$k8055 = RubyK8055.new
$k8055.connect
$k8055.clear_all_digital

$lastOctopusID = ""

$lcdTimeThread = nil

# A custom default message, based on the current date
def motd
  time = hk_time
  return case [time.day, time.month]
    when [25, 12] then "  Merry Christmas!  "
    when easter(time.year) then "  Jesus is Alive!   "
    when [5,  10] then " Happy B'day Masha! "
    when [3,  6]  then "Happy B'day Nathan! "
    else " Octopus & Internet "    # else, default message
  end
end

def lcd_message(str, s_pos=21, e_pos=40, timeout=true)
  # Kill 'clock' thread before writing message.
  if $lcdTimeThread
    $lcdTimeThread.kill
    $lcdTimeThread = nil
  end
  $dsp420.write str, s_pos, e_pos
  if timeout
    sleep MsgDelay
    lcd_default
  end
end

def lcd_default   # Default lcd display
  lcd_message "Flat 10C -=-        ", 1, 20, false
  lcd_message motd, 21, 40, false

  $lcdTimeThread = Thread.new {
    while true
      time = hk_time
      $dsp420.write lcd_time_fmt(time, ":"), 14, 20, false
      sleep 1
      $dsp420.write lcd_time_fmt(time, " "), 14, 20, false
      sleep 1
      # If its the start of a new day, refresh the message.
      if time.hour == 0 and time.min == 0 and time.sec < 3
        lcd_message motd, 21, 40, false
      end
    end
  }
end

# Every good program should calculate the date of Easter at least once.
def easter(year)
  c=year/100;n=year-19*(year/19);k=(c-17)/25;i=c-c/4-(c-k)/3+19*n+15;i-=30*(i/30);
  i-=(i/28)*(1 -(i/28)*(29/(i+1))*((21-n)/11));j=year+year/4+i+2-c+c/4;j-=7*(j/7);
  l=i-j;month=3+(l+40)/44;day=l+28-31*(month/4);
  [day, month]
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
  $users.map {|name, params| "<option #{name == @user ? 'selected="true"' : ''}value=\"#{name}\">#{name}</option>" }.join
end

# Evo T20 is synced to UTC. HK time is UTC - 3 hours
def hk_time
  Time.now - 3*60*60
end

def hk_time_fmt
  hk_time.strftime("%Y-%m-%d %H:%M:%S")
end

def lcd_time_fmt(time = hk_time, separator = ":")
  hour, minute = time.hour, time.min
  hour, suffix = hour >= 12 ? [hour - 12, "pm"] : [hour, "am"]
  hour = 12 if hour == 0
  "%2d#{separator}%02d%s" % [hour, minute, suffix]
end

def xbmc_trigger(name)
  # Send a trigger to xbmc server if user has any configured radio preferences.
  # (and if the time is reasonable. AND if nothing is already playing on XBMC.)
  time = hk_time
  if time.hour >= 7 and time.hour <= 22 and not xbmc_playing? and not xbmc_video_paused?
    if radio_prefs = YAML.load_file(relative("config/user_radio_prefs.yml"))
      if stations = radio_prefs[name]
        # Pick a random station, and play it.
        station = stations[rand(stations.size)]
        # Set volume to 45
        xbmc_api("XBMC.SetVolume", 40)
        # Play the station.
        xbmc_api("XBMC.Play", %Q[{"file":"#{station.gsub(" ", "%20")}"}], :ignore)
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
  @user, @password = "", ""
  erb :index
end

get '/octopus/:id' do
  # If user can authenticate
  if user = $users.detect {|u| u[1]["octopus_id"] == params[:id] }
    name = user[0]
    unlock_door_action
    @message = "  [#{params[:id]}]  " +
               "Welcome, #{name.split.first}!"
    lcd_message @message, 1, 40, true

    # Post unlock actions
    # ------------------------------------------
    hall_light_trigger unless $hall_light_on

    # --- Start playing some lastfm on xbmc, if appropriate time.
    xbmc_trigger(name)
  else
    access_denied_action
    $lastOctopusID = params[:id]
    @message = "  [#{params[:id]}]  " +
               "  Access Denied."
    lcd_message @message, 1, 40, true
  end
  return ""
end

post '/action' do
  # If user can authenticate
  user = $users[params[:user]]
  if user && user['http_pwd'] && user['http_pwd'] == params[:password]
    # save user and password in returned page
    @user, @password = params[:user], params[:password]

    # Process requested action.

    # Kill hall light timed thread, if running
    if params[:action].include?("Hall Light")
      $hall_light_thread.kill if $hall_light_thread
      $hall_light_thread = nil
    end

    @message = ""
    case params[:action]
    when "Unlock Door"
      name = params[:user]
      unlock_door_action
      @message = "Welcome, #{name.split.first}!"

      # Post unlock actions
      # ------------------------------------------
      hall_light_trigger unless $hall_light_on

      xbmc_trigger(name)
    when "Turn Hall Light [ON]"
      unless $hall_light_on
        $k8055.set_digital HallLightChannel, false
        $hall_light_on = true
        @message = "Hall light is on."
      end
    when "Turn Hall Light [OFF]"
      if $hall_light_on
        $k8055.set_digital HallLightChannel, false
        $hall_light_on = false
        @message = "Hall light is off."
      end
    when "Keep Hall Light [ON]"
      # Hall light thread is already killed above.
      @message = "Light will stay on."
    when "Turn Fan [ON]"
      unless $fan_on
        $k8055.set_digital FanChannel, false
        $fan_on = true
        @message = "Fan is on."
      end
    when "Turn Fan [OFF]"
      if $fan_on
        $k8055.set_digital FanChannel, false
        $fan_on = false
        @message = "Fan is off."
      end
    when "Turn Umbrella Bucket [ON]"
      unless $umbrella_on
        $k8055.set_digital UmbrellaChannel, false
        $umbrella_on = true
        @message = "Umbrella bucket is on."
      end
    when "Turn Umbrella Bucket [OFF]"
      if $umbrella_on
        $k8055.set_digital UmbrellaChannel, false
        $umbrella_on = false
        @message = "Umbrella bucket is off."
      end
    when "Edit Authorizations"
      # Edit authorized users list
      @filename = File.join(File.dirname(__FILE__), "config/authorized_users.yml")
      @data = File.open(@filename, "r").read
      return erb :edit_users
    end

    # Display LCD message for action
    lcd_message "  HTTP - #{ @env['REMOTE_ADDR'] } ", 1, 20, false
    lcd_message @message, 21, 40, true
  else
    access_denied_action
    lcd_message "  HTTP - #{ @env['REMOTE_ADDR'] } ", 1, 20, false
    @message =  "  Access Denied."
    lcd_message @message, 21, 40, true
  end

  erb :index
end

get '/umbrella_bucket/:state' do
  case params[:state]
  when "on"
    unless $umbrella_on
      $k8055.set_digital UmbrellaChannel, false
      $umbrella_on = true
    end
  when "off"
    if $umbrella_on
      $k8055.set_digital UmbrellaChannel, false
      $umbrella_on = false
    end
  end
end

# To manually update time.
get '/gettime' do
  `sudo /usr/bin/getTime.sh &`
  return ""
end

post '/edit_users' do
  @filename = File.join(File.dirname(__FILE__), "config/authorized_users.yml")
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

