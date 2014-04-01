require "./web_stream"

$stdout.sync = true

map('/subscribe')   { run WebStreamer }
