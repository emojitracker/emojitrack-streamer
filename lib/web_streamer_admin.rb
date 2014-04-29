################################################
# admin stuff
################################################

class WebStreamerAdmin < Sinatra::Base

  module ReportingUtils
    STREAM_STATUS_REDIS_KEY = 'admin_stream_status'
    STREAM_STATUS_UPDATE_RATE = 5

    def self.current_status
      {
        'node'        => self.node_name,
        'status'      => 'OK',
        'reported_at' => Time.now.to_i,
        'connections' => {
          'stream_raw'    => WebScoreRawStreamer.connections.map(&:to_hash),
          'stream_eps'    => WebScoreCachedStreamer.connections.map(&:to_hash),
          'stream_detail' => WebDetailStreamer.connections.map(&:to_hash)
        }
      }
    end

    def self.node_name
      @node_name ||= 'mri-' + ENV['RACK_ENV'] + '-' + (ENV['DYNO'] || 'unknown')
    end

    def self.push_node_status_to_redis
      REDIS.HSET STREAM_STATUS_REDIS_KEY, self.node_name, Oj.dump(self.current_status)
    end

  end

  #
  # periodically log the updates to admin reporter
  #
  EM.next_tick do
    EM.add_periodic_timer(ReportingUtils::STREAM_STATUS_UPDATE_RATE) do
      ReportingUtils.push_node_status_to_redis
    end
  end

  #
  # graphite logging for all the streams
  #
  @stream_graphite_log_rate = 10
  EM.next_tick do
    EM::PeriodicTimer.new(@stream_graphite_log_rate) do
      graphite_dyno_log("stream.raw.clients",     WebScoreRawStreamer.connections.count)
      graphite_dyno_log("stream.eps.clients",     WebScoreCachedStreamer.connections.count)
      graphite_dyno_log("stream.detail.clients",  WebDetailStreamer.connections.count)
    end
  end

  #
  # expose HTTP endpoints for querying status
  #
  helpers ReportingUtils

  get '/admin/?' do
    redirect '/admin/', 301
  end

  get '/admin/status.json' do
    content_type :json
    Oj.dump ReportingUtils.current_status
  end
end
