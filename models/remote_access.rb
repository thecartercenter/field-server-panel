require "json"
require "open-uri"

# Sets up and maintains a remote access tunnel.
class RemoteAccess < Module
  attr_accessor :config, :enabled

  def initialize(config)
    self.config = config
    self.enabled = true
  end

  def start(mode)
    raise ArgumentError, "invalid mode" unless %w[ssh https].include?(mode)
    write_log("Starting #{mode}", append: false)
    write_status(:starting)
    File.delete(kill_file_path) if File.exist?(kill_file_path)
    script_path = File.join(config["app_root"], "scripts", "runngrok")
    spawn("sudo", script_path, ngrok_mode(mode), port(mode), log_path)
  rescue StandardError => e
    write_log(e)
    write_status(:failed)
  end

  def close
    write_log("Closing remote access...")
    FileUtils.touch(kill_file_path)
    sleep(1)
    write_log("Remote access closed.")
    write_status(:closed)
  rescue Errno::EPERM
    write_log("Error closing remote access: No permission to query #{signal['pid']}.")
  rescue Errno::ESRCH
    write_log("Error closing remote access: PID #{signal['pid']} is not running.")
  end

  # Can be starting, failed, running, or closed
  def status
    return @status if @status
    @status = super
    begin
      response = JSON.parse(open("http://localhost:4040/api/tunnels").string)
      if response.is_a?(Hash) && (tunnels = response["tunnels"]) && tunnels.any?
        @status["status"] = "running" # Overwrites 'starting' status in file.
        @status["url"] = tunnels[0]["public_url"]
      end
    rescue Errno::ECONNREFUSED
      @status["status"] = "closed" unless @status["status"] == "failed"
    end
    @status
  end

  def url
    status["url"]
  end

  protected

  def port(mode)
    (mode == "ssh" ? (config["ssh_port"] || 22) : 443).to_s
  end

  def ngrok_mode(mode)
    mode == "ssh" ? "tcp" : "http"
  end

  def module_name
    "remote"
  end

  def kill_file_path
    @kill_file_path ||= File.join(dir, "kill")
  end
end
