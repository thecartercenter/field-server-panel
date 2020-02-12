require "fileutils"
require "json"
require "open-uri"

# Sets up and maintains a remote access tunnel.
class RemoteAccess
  attr_accessor :config, :enabled

  def initialize(config)
    self.config = config
    self.enabled = true
  end

  def start
    write_log("Starting", append: false)
    write_status(:starting)
    pid = spawn("ngrok", "tcp", (config["ssh_port"] || 22).to_s, "-log=stdout",
      %i[out err] => [log_path, "a"])
    write_status(:starting, "pid" => pid)
  rescue StandardError => e
    write_log(e)
    write_status(:failed)
    raise e # Re-raise error so full backtrace gets logged to server log.
  end

  def close
    if status["pid"]
      Process.kill("HUP", status["pid"])
      write_log("Remote access closed.")
    else
      write_log("Error closing remote access: PID is not stored.")
    end
  rescue Errno::EPERM
    write_log("Error closing remote access: No permission to query #{signal['pid']}.")
  rescue Errno::ESRCH
    write_log("Error closing remote access: PID #{signal['pid']} is not running.")
  end

  def status
    return @status if @status
    @status = begin
                YAML.safe_load(File.read(File.join(dir, "status.yml")))
              rescue Errno::ENOENT
                {}
              end
    begin
      response = JSON.parse(open("http://localhost:4040/api/tunnels").string)
      if response.is_a?(Hash) && (tunnels = response["tunnels"]) && tunnels.any?
        @status["status"] = "open" # Overwrites 'starting' status in file.
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

  def log
    @log ||= File.read(File.join(dir, "log"))
  rescue Errno::ENOENT
    nil
  end

  def fresh?
    status["status"].nil?
  end

  def open?
    enabled? && status["status"] == "open"
  end

  def succeeded?
    status["status"] == "succeeded"
  end

  def failed?
    status["status"] == "failed"
  end

  def starting?
    status["status"] == "starting"
  end

  def enabled?
    enabled
  end

  private

  def dir
    File.join(config["tmp_dir"], "remote")
  end

  def ensure_dir
    FileUtils.mkdir_p(dir)
  end

  def log_path
    @log_path ||= File.join(dir, "log")
  end

  def write_log(message, append: true)
    ensure_dir
    File.open(log_path, append ? "a" : "w") { |f| f.puts("[#{timestamp}] #{message}") }
  end

  def status_path
    @status_path ||= File.join(dir, "status.yml")
  end

  def write_status(name, data = {})
    ensure_dir
    File.open(status_path, "w") do |file|
      file.puts(YAML.dump(data.merge("status" => name.to_s, "time" => timestamp)))
    end
    true
  end

  def timestamp
    Time.now.utc.strftime("%Y-%m-%d %H:%M:%S UTC")
  end
end
