require "sinatra"
require "yaml"
require "sys/filesystem"
require_relative "models/backup"

Tilt.register(Tilt::ERBTemplate, "html.erb")

# Main app and routes.
configure :production do
  set :clean_trace, true
end

configure :development do
end

helpers do
  include Rack::Utils
  alias_method :h, :escape_html
end

before do
  # We never want to cache any of our pages.
  expires(0, :no_store, :no_cache, :must_revalidate)
end

get "/" do
  erb(:main)
end

get "/backup" do
  @config = load_config("backup")
  @title = "Backup"
  begin
    stat = Sys::Filesystem.stat(@config["dest_path"])
    @space_left_gib = (stat.blocks_available.to_f * stat.block_size / 2**30).round(1)
    @backups = `borg list #{@config["dest_path"]} --format "{archive}, {time}{NL}"`.split("\n")
  rescue Sys::Filesystem::Error => e
    @dest_missing = true
  end
  @status = begin
              YAML.safe_load(File.read(File.join(@config["tmp_dir"], "backup", "status.yml")))
            rescue Errno::ENOENT
              nil
            end
  @log = begin
           File.read(File.join(@config["tmp_dir"], "backup", "log"))
         rescue Errno::ENOENT
           nil
         end
  erb(:backup)
end

post "/backup/run" do
  Process.fork do
    settings.running_server = nil # Don't terminate web server when process finishes.
    Backup.new(load_config("backup")).run
  end
end

post "/backup/reset" do
  Backup.new(load_config("backup")).reset
end

def load_config(key)
  config = YAML.safe_load(File.read(File.join(settings.root, "config.yml")))
  raise "#{key} config missing" unless config.is_a?(Hash) && config.key?(key)
  config[key]["tmp_dir"] = File.join(settings.root, "tmp")
  config[key]
end
