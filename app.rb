require "sinatra"
require "yaml"
require "sys/filesystem"
require_relative "models/module"
require_relative "models/backup"
require_relative "models/remote_access"

Tilt.register(Tilt::ERBTemplate, "html.erb")

use Rack::Auth::Basic, "Protected Area" do |username, password|
  config = load_config("auth")
  username == config["username"] && password == config["password"]
end

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
  @title = "Welcome"
  erb(:main)
end

get "/backup" do
  @config = load_config("backup")
  @title = "Backup"
  @backup = Backup.new(@config)
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

get "/remote" do
  @config = load_config("remote")
  @title = "Remote Access"
  @remote = RemoteAccess.new(@config)
  erb(:remote)
end

post "/remote/start" do
  Process.fork do
    settings.running_server = nil # Don't terminate web server when process finishes.
    RemoteAccess.new(load_config("remote")).start
  end
  sleep(1) # Allow enough time for 'starting' status to be written.
end

post "/remote/close" do
  RemoteAccess.new(load_config("remote")).close
  redirect("/remote")
end

def load_config(key)
  config = YAML.safe_load(File.read(File.join(settings.root, "config.yml")))
  raise "#{key} config missing" unless config.is_a?(Hash) && config.key?(key)
  config[key]["app_root"] = settings.root
  config[key]["tmp_dir"] = File.join(settings.root, "tmp")
  config[key]
end
