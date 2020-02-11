# Performs a backup.
class Backup
  attr_accessor :config

  def initialize(config)
    self.config = config
  end

  def run
    log("Starting", append: false)
    write_status(:running)

    if config["database"]
      db_dump_path = File.join(config["source_paths"][0], "db-snapshot")
      log("Dumping database to #{db_dump_path}...")
      unless system("pg_dump -Fc #{config['database']} > #{db_dump_path} 2>> #{log_path}")
        write_status(:failed) && return
      end
      log("Database dump complete.")
    end

    unless system("borg info #{config['dest_path']}")
      log("Creating backup repository...")
      unless system("borg init #{config['dest_path']} -e none >> #{log_path} 2>> #{log_path}")
        write_status(:failed) && return
      end
      log("Repository creation complete.")
    end

    log("Performing backup...")
    prefix = begin
               File.read(config["id_file"]).strip
             rescue Errno::ENOENT
               log("Could not find volume name; check id_file config")
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
    log("Backup complete.")

    log("Pruning old backups...")
    daily = config.dig("retention", "daily") || 7
    weekly = config.dig("retention", "weekly") || 4
    res = system("borg prune -v --list --keep-daily=#{daily} --keep-weekly=#{weekly} #{config['dest_path']}"\
      ">> #{log_path} 2>> #{log_path}")
    write_status(:failed) && return unless res
    log("Pruning complete.") if res
  rescue StandardError => e
    log(e)
    write_status(:failed)
    raise e # Re-raise error so full backtrace gets logged to server log.
  else
    write_status(:succeeded)
  end

  def reset
    write_status(:failed)
  end

  private

  def log_path
    @log_path ||= File.join(config["tmp_dir"], "backup", "log")
  end

  def log(message, append: true)
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
