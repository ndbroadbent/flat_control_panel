module XBMC
  def xbmc_api(method, params="{}", ignore_response=false)
    url = URI.parse($config["xbmc_url"])
    req = Net::HTTP::Post.new(url.path)
    req.basic_auth $config["xbmc_username"], $config["xbmc_password"]
    req.add_field 'Content-Type', 'application/json'
    req.body = %Q[{"method":"#{method}","params":#{params},"id":1,"jsonrpc":"2.0"}]
    begin
      # fetch ip from system nslookup. ruby seems to hang a lot on DNS lookups.
      if ip_addr = `nslookup #{url.host}`[Regexp.new('Address 1: (\d+\.\d+\.\d+\.\d+) ' << url.host), 1]
        res = Net::HTTP.new(ip_addr, url.port).start do |http|
          # Don't need to stick around for the response.
          http.read_timeout = 2 if ignore_response
          http.request(req)
        end
      end
    rescue Timeout::Error
    end
    return ignore_response ? true : res
  end

  def xbmc_playing?
    xbmc_audio_playing? || xbmc_video_playing?
  end

  def xbmc_audio_playing?
    players = eval(xbmc_api("Player.GetActivePlayers").body.gsub(":", "=>"))["result"]
    players["audio"] && !eval(xbmc_api("AudioPlayer.State").body.gsub(":", "=>"))["result"]["paused"]
  end

  # The following two methods are not the inverse of each other, since they are
  # dealing with the boolean representation of three separate states.
  # ----------------------------------------------------------------------------
  #    playing,  !paused, !stopped =>  xbmc_video_playing?
  #   !playing,   paused,  stopped => !xbmc_video_playing?
  #   !playing,   paused, !stopped =>  xbmc_video_paused?
  #    playing,  !paused,  stopped => !xbmc_video_paused?
  #
  #   !playing,  !paused,  stopped => !xbmc_video_playing && !xbmc_video_paused
  # ----------------------------------------------------------------------------
  # => nothing playing, and video not paused => !xbmc_playing? && !xbmc_video_paused?

  def xbmc_video_playing?
    players = eval(xbmc_api("Player.GetActivePlayers").body.gsub(":", "=>"))["result"]
    players["video"] && !eval(xbmc_api("VideoPlayer.State").body.gsub(":", "=>"))["result"]["paused"]
  end
  def xbmc_video_paused?
    players = eval(xbmc_api("Player.GetActivePlayers").body.gsub(":", "=>"))["result"]
    return false unless players["video"]
    return eval(xbmc_api("VideoPlayer.State").body.gsub(":", "=>"))["result"]["paused"]
  end

end

