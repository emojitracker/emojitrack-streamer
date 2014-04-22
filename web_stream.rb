require 'sinatra/base'
require 'oj'
require 'eventmachine'
require_relative 'lib/config'
require_relative 'lib/wrapped_stream'
require_relative 'lib/web_streamer_admin'

##############################################################
# configure defaults around forced SSE timeouts and the like
##############################################################
SSE_SCORE_RETRY_MS        = ENV['SSE_SCORE_RETRY_MS']        || 100
SSE_DETAIL_RETRY_MS       = ENV['SSE_DETAIL_RETRY_MS']       || 500
SSE_SCORE_FORCECLOSE_SEC  = ENV['SSE_SCORE_FORCECLOSE_SEC']  || 300
SSE_DETAIL_FORCECLOSE_SEC = ENV['SSE_DETAIL_FORCECLOSE_SEC'] || 300

SSE_FORCE_REFRESH               = to_boolean(ENV['SSE_FORCE_REFRESH']               || 'false')
ENABLE_RAW_STREAM               = to_boolean(ENV['ENABLE_RAW_STREAM']               || 'true')
ENABLE_KIOSK_INTERACTION_STREAM = to_boolean(ENV['ENABLE_KIOSK_INTERACTION_STREAM'] || 'false')

################################################
# convenience method for stream connect logging
################################################
def log_connect(stream_obj)
  puts "STREAM: connect for #{stream_obj.request_path} from #{request.ip}" if VERBOSE
  # REDIS.PUBLISH 'stream.admin.connect', stream_obj.to_json
end

def log_disconnect(stream_obj)
  puts "STREAM: disconnect for #{stream_obj.request_path} from #{request.ip}" if VERBOSE
  # REDIS.PUBLISH 'stream.admin.disconnect', stream_obj.to_json
end

################################################
# convenience methods for all SSE stream classes
################################################
module SSEHelpers
  def sse_headers()
    headers("Access-Control-Allow-Origin" => "*" )
    headers("Cache-Control" => "no-cache")
    headers("X-Sse-Cleanup-Requested" => 'true') if SSE_FORCE_REFRESH
    content_type 'text/event-stream'
  end
end

################################################
# streamer for score updates (main page)
################################################
class WebScoreRawStreamer < Sinatra::Base
  helpers SSEHelpers
  before { sse_headers() }

  set :connections, []

  get '/raw' do
    stream(:keep_open) do |out|
      out = WrappedStream.new(out, request)
      out.sse_set_retry(SSE_SCORE_RETRY_MS) if SSE_FORCE_REFRESH
      settings.connections << out
      log_connect(out)
      out.callback { log_disconnect(out); settings.connections.delete(out) }

      if SSE_FORCE_REFRESH then EM.add_timer(SSE_SCORE_FORCECLOSE_SEC) { out.close } end
    end
  end

  #
  # Spawn a thread to subscribe to Redis score updates and push them out to
  # clients on the raw endpoint.  We don't need to do anything except pass the
  # message directly here.
  #
  # Allow thread to be disabled since we arent using it for anything official
  # now and will save on redis connections.
  #
  if ENABLE_RAW_STREAM
    Thread.new do
      t_redis = connect_redis()
      t_redis.psubscribe('stream.score_updates') do |on|
        on.pmessage do |match, channel, message|
          connections.each { |out| out.sse_data(message) }
        end
      end
    end
  end

end

################################################
# 60 events-per-second rollup streamer for score updates
################################################
class WebScoreCachedStreamer < Sinatra::Base
  helpers SSEHelpers
  before { sse_headers() }

  set :connections, []
  cached_scores = {}
  semaphore = Mutex.new

  get '/eps' do
    stream(:keep_open) do |out|
      out = WrappedStream.new(out, request)
      out.sse_set_retry(SSE_SCORE_RETRY_MS) if SSE_FORCE_REFRESH
      settings.connections << out
      log_connect(out)
      out.callback { log_disconnect(out); settings.connections.delete(out) }

      if SSE_FORCE_REFRESH then EM.add_timer(SSE_SCORE_FORCECLOSE_SEC) { conn.close } end
    end
  end

  #
  # Spawn a thread to periodically flush the score cache out to all connections.
  #
  Thread.new do
    scores = {}

    loop do
      # Obtain a mutex lock on the cache just long enough to get a copy of the
      # values and then reset the cache, this way the update thread can continue
      # filling the cache without being blocked while this thread is writing the
      # past update out to any subscribed clients.
      semaphore.synchronize do
        scores = cached_scores.clone
        cached_scores.clear
      end

      # Write the packed score update out to all subscribed clients.
      unless scores.empty?
        encoded_score_update = Oj.dump scores
        connections.each { |out| out.sse_data(encoded_score_update) }
      end

      # Wait long enough so that we're emitting at approximately 60fps
      sleep 0.017 # 1/60.0 rounded up
    end
  end

  #
  # Spawn a thread to continuously read score_updates from Redis and push them
  # into the rollup cache.
  #
  Thread.new do
    t_redis = connect_redis()
    t_redis.psubscribe('stream.score_updates') do |on|
      on.pmessage do |match, channel, message|
        semaphore.synchronize do
          cached_scores[message] ||= 0
          cached_scores[message] += 1
        end
      end
    end

  end

end

################################################
# streaming thread for tweet updates (detail pages)
################################################
class WebDetailStreamer < Sinatra::Base
  helpers SSEHelpers
  before { sse_headers() }

  set :connections, []

  get '/details/:char' do
    stream(:keep_open) do |out|
      tag = params[:char]
      out = WrappedStream.new(out, request, tag)
      out.sse_set_retry(SSE_DETAIL_RETRY_MS) if SSE_FORCE_REFRESH
      settings.connections << out
      log_connect(out)
      out.callback { log_disconnect(out); settings.connections.delete(out) }

      if SSE_FORCE_REFRESH then EM.add_timer(SSE_DETAIL_FORCECLOSE_SEC) { out.close } end
    end
  end

  #
  # Spawn a thread to pattern match subscribe to all tweet updates from redis.
  #
  # We then examine the Redis channel to get the UID for the matching namespace,
  # and only send to connections that are tagged with that namespace. The
  # original Redis channel is used as the SSE event name.
  #
  Thread.new do
    t_redis = connect_redis()
    t_redis.psubscribe('stream.tweet_updates.*') do |on|
      on.pmessage do |match, channel, message|
        channel_id = channel.split('.')[2]
        connections.select { |c| c.match_tag?(channel_id) }.each do |conn|
          conn.sse_event_data(channel, message)
        end
      end
    end
  end

end

################################################
# streamer for kiosk interaction
################################################
class WebKioskInteractionStreamer < Sinatra::Base
  helpers SSEHelpers
  before { sse_headers() }

  set :connections, []

  get '/kiosk_interaction' do
    stream(:keep_open) do |out|
      out = WrappedStream.new(out, request)
      settings.connections << out
      log_connect(out)
      out.callback { log_disconnect(out); settings.connections.delete(out) }
    end
  end

  #
  # Spawn a thread to rebroadcast anything from the `stream.interaction.*` Redis
  # channel to interested clients.
  #
  # We are just an intermediary here to allow commands to be sent upstream that
  # propogate to clients.  Normal clients won't subscribe to this endpoint, as
  # it was only used for the #emojiartshow thus far, so allow it to be disabled
  # to save a Redis connection.
  #
  if ENABLE_KIOSK_INTERACTION_STREAM
    Thread.new do
      puts "SUBSCRIBING TO KIOSK INTERACTIVE STREAM YO"
      t_redis = connect_redis()
      t_redis.psubscribe('stream.interaction.*') do |on|
        on.pmessage do |match, channel, message|
          connections.each { |out| out.sse_data(channel, message) }
        end
      end
    end
  end

end


################################################
# main master class for the app
################################################
class WebStreamer < Sinatra::Base

  use WebKioskInteractionStreamer if ENABLE_KIOSK_INTERACTION_STREAM
  use WebScoreRawStreamer         if ENABLE_RAW_STREAM
  use WebScoreCachedStreamer
  use WebDetailStreamer
  use WebStreamerAdmin


  ################################################
  # load newrelic in production
  #  - even though it logs little with streams,
  #    we can still use to profile memory.
  ################################################
  configure :production, :staging do
    require 'newrelic_rpm'
  end

  ################################################
  # cleanup methods for force a stream disconnect on servers like heroku where server cant detect it :(
  ################################################
  before do
    headers("Access-Control-Allow-Origin" => "*" )
    headers("Cache-Control" => "no-cache")
  end

  post '/cleanup/scores' do
    puts "CLEANUP: force scores disconnect for #{request.ip}" if VERBOSE
    matched_conns = WebScoreCachedStreamer.connections.select { |conn| conn.client_ip == request.ip }
    matched_conns.each(&:close)
    content_type :json
    Oj.dump( { 'status' => 'OK', 'closed' => matched_conns.count } )
  end

  post '/cleanup/details/:id' do
    id = params[:id]
    puts "CLEANUP: force details #{id} disconnect for #{request.ip}" if VERBOSE
    matched_conns = WebDetailStreamer.connections.select { |conn| conn.client_ip == request.ip  && conn.tag == id}
    matched_conns.each(&:close)
    content_type :json
    Oj.dump( { 'status' => 'OK', 'closed' => matched_conns.count } )
  end

end
