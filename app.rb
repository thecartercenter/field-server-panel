require "sinatra"

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

get "/" do
  erb(:main)
end
