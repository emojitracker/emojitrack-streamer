# emojitrack-streamer
Handles emojitracker's SSE endpoints for streaming realtime updates to web clients.

Overall responsibilities:

 * Consumes all the PUBSUB update streams from Redis.
 * Implements a "score summarizer" pipeline, converting the primary `score_updates` stream from atomic updates (currently incoming at a typical rate of 250-400Hz) to rolled-up summary blobjects emitted at a maximum rate of 60Hz.
 * Accepts client connections on SSE endpoint pools.
   - Namespace connections based on request path resource IDs, allowing a client to subscribe to updates on arbitrary objects.
   - Performs filter operations so that `detail` updates are only sent to SSE streams with interested clients connected.
   - Multiplex all streams to clients appropriately.

Additionally we must:
 * Periodically reports on status of the connection pools to the admin cluster.
 * Periodically log status of the connection pools to graphite.

### Legacy note

This represents the original version of emojitracker's SSE streaming functionality, being isolated into it's own service so that it can either be more easily improved or swapped out later.  It is being moved "as is" as much as possible for now.  Most importantly by moving this into it's own service we can horizontally scale streaming independently of the normal web frontend/API.

This version uses MRI Ruby threads for concurrency, but has EventMachine reactor stuff sprinkled in for timers and whatnot. (Told you it was a bit of a mess!)

Unlike the new [experimental NodeJS version of emojitrack-streamer](http://github.com/mroth/emojitrack-nodestreamer), this version still has the ability to manually manage client socket connections via `SSE_RECONNECT` timing, forced disconnects, and exposing AJAX endpoints for clients to manually indicate when they are done with a resource.  This enables it to work in environments where websocket-style connections are not natively supported (for example, behind Heroku's routing later if you don't have the websockets lab project enabled.)

## Streaming API
This implementation defined the original API spec, but the source of truth for the spec is now defined in [emojitrack-streamer-spec](https://github.com/mroth/emojitrack-streamer-spec).  Go there for streaming API documentation and acceptance tests.

## Developer setup
Instructions to go here.


## Other parts of emojitracker
This is but a small part of emojitracker's infrastructure.  Major components of the project include:

 - [emojitrack-web](//github.com/mroth/emojitrack)
 - emojitrack-streamer
    * [ruby version](//github.com/mroth/emojitrack-streamer) (current)
    * [nodejs version](//github.com/mroth/emojitrack-nodestreamer) (experimental)
    * [streamer API spec](//github.com/mroth/emojitrack-streamer-spec)
 - [emojitrack-feeder](//github.com/mroth/emojitrack-feeder)

Many of the libraries emojitrack uses have also been carved out into independent open-source projects, see the following:

 - [emoji_data.rb](http://github.com/mroth/emoji_data.rb)
 - [emojistatic](http://github.com/mroth/emojistatic)
