require "fileutils"

# An area of the system that has a status, log file, etc.
class Module
  attr_accessor :config, :enabled

  def initialize(config)
    self.config = config
    self.enabled = true
  end

  def log
    @log ||= File.read(File.join(dir, "log"))
  rescue Errno::ENOENT
    nil
  end

  def status
    YAML.safe_load(File.read(File.join(dir, "status.yml")))
  rescue Errno::ENOENT
    {}
  end

  def fresh?
    status["status"].nil?
  end

  def running?
    enabled? && status["status"] == "running"
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

  def closed?
    status["status"] == "closed"
  end

  def enabled?
    enabled
  end

  private

  def dir
    File.join(config["tmp_dir"], module_name)
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
