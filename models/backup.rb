# Performs a backup.
class Backup
  attr_accessor :config, :free_space_gib, :enabled

  def initialize(config)
    self.config = config
    stat = Sys::Filesystem.stat(config["dest_path"])
    self.free_space_gib = (stat.blocks_available.to_f * stat.block_size / 2**30).round(1)
    self.enabled = true
  rescue Sys::Filesystem::Error => e
    self.enabled = false
  end

  def run
    write_log("Starting", append: false)
    write_status(:running)

    if config["database"]
      db_dump_path = File.join(config["source_paths"][0], "db-snapshot")
      write_log("Dumping database to #{db_dump_path}...")
      unless system("pg_dump -Fc #{config['database']} > #{db_dump_path} 2>> #{log_path}")
        write_status(:failed) && return
      end
      write_log("Database dump complete.")
    end

    unless system("borg info #{config['dest_path']}")
      write_log("Creating backup repository...")
      unless system("borg init #{config['dest_path']} -e none >> #{log_path} 2>> #{log_path}")
        write_status(:failed) && return
      end
      write_log("Repository creation complete.")
    end

    write_log("Performing backup...")
    prefix = begin
               File.read(config["id_file"]).strip
             rescue Errno::ENOENT
               write_log("Could not find volume name; check id_file config")
               write_status(:failed)
               return
             end
    suffix = Time.now.utc.strftime("%Y%m%d%H%M%S")
    source_paths = config["source_paths"].join(" ")
    res = system("borg create --verbose --filter AME --list --stats --show-rc "\
      "--compression lz4 --exclude-caches "\
      "#{config['dest_path']}::#{prefix}-#{suffix} #{source_paths} "\
      ">> #{log_path} 2>> #{log_path}")
    write_status(:failed) && return unless res
    write_log("Backup complete.")

    write_log("Pruning old backups...")
    daily = config.dig("retention", "daily") || 7
    weekly = config.dig("retention", "weekly") || 4
    res = system("borg prune -v --list --keep-daily=#{daily} --keep-weekly=#{weekly} #{config['dest_path']}"\
      ">> #{log_path} 2>> #{log_path}")
    write_status(:failed) && return unless res
    write_log("Pruning complete.") if res
  rescue StandardError => e
    write_log(e)
    write_status(:failed)
    raise e # Re-raise error so full backtrace gets logged to server log.
  else
    write_status(:succeeded)
  end

  def reset
    write_status(:failed)
  end

  def list
    return nil if running?
    return @list if defined?(@list)
    @list = `borg list #{config["dest_path"]} --format "{archive}, {time} UTC{NL}"`.split("\n")
    @list = @list.map do |b|
      b.split(", ").tap do |x|
        x[0] = x[0].match(/\A(\w+)-\d+\z/)[1] # Remove numeric suffix
        x[1] = nil # Remove weekday
      end.compact.join(", ")
    end
  end

  def status
    @status ||= YAML.safe_load(File.read(File.join(config["tmp_dir"], "backup", "status.yml")))
  rescue Errno::ENOENT
    @status = {}
  end

  def log
    @log ||= File.read(File.join(config["tmp_dir"], "backup", "log"))
  rescue Errno::ENOENT
    nil
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

  def enabled?
    enabled
  end

  private

  def log_path
    @log_path ||= File.join(config["tmp_dir"], "backup", "log")
  end

  def write_log(message, append: true)
    File.open(log_path, append ? "a" : "w") { |f| f.puts("[#{timestamp}] #{message}") }
  end

  def status_path
    @status_path ||= File.join(config["tmp_dir"], "backup", "status.yml")
  end

  def write_status(name)
    File.open(status_path, "w") { |f| f.puts(YAML.dump("status" => name.to_s, "time" => timestamp)) }
    true
  end

  def timestamp
    Time.now.utc.strftime("%Y-%m-%d %H:%M:%S UTC")
  end
end
