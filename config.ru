configure :production do
  require 'newrelic_rpm'
end

require "./web_stream"

$stdout.sync = true

map('/subscribe')   { run WebStreamer }
