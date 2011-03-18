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
    players = eval(xbmc_api("Player.GetActivePlayers").body.gsub(":", "=>"))["result"]
    player = if players["audio"]
      "AudioPlayer"
    elsif players["video"]
      "VideoPlayer"
    else
      nil
    end
    return false unless player
    return !eval(xbmc_api("#{player}.State").body.gsub(":", "=>"))["result"]["paused"]
  end
end

