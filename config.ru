require "./web_stream"

$stdout.sync = true

map('/')   { run WebStreamer }
