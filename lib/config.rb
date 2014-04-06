require 'redis'
require 'uri'
require 'socket'

#convenience method for reading booleans from env vars
def to_boolean(s)
  s and !!s.match(/^(true|t|yes|y|1)$/i)
end

# verbose mode or no
VERBOSE = to_boolean(ENV["VERBOSE"]) || false
puts "*** Starting in VERBOSE mode" if VERBOSE

# db setup
REDIS_URI = URI.parse(ENV["REDIS_URL"] || ENV["BOXEN_REDIS_URL"] || "redis://localhost:6379")
REDIS = Redis.new(:host => REDIS_URI.host, :port => REDIS_URI.port, :password => REDIS_URI.password, :driver => :hiredis)

# environment checks
def is_production?
  ENV["RACK_ENV"] == 'production'
end

def is_development?
  ENV["RACK_ENV"] == 'development'
end

# configure logging to graphite in production
@hostedgraphite_apikey = ENV['HOSTEDGRAPHITE_APIKEY']
if is_production? && !@hostedgraphite_apikey
  puts "Did not find an API key for hostedgraphite, will not log..."
end

def graphite_log(metric, count)
  if is_production?
    if @hostedgraphite_apikey
      sock = UDPSocket.new
      sock.send @hostedgraphite_apikey + ".#{metric} #{count}\n", 0, "carbon.hostedgraphite.com", 2003
    end
  end
end

# same as above but include heroku dyno hostname
def graphite_dyno_log(metric,count)
  dyno = ENV['DYNO'] || 'unknown-host'
  metric_name = "#{dyno}.#{metric}"
  graphite_log metric_name, count
end
