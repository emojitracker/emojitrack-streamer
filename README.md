# emojitrack-streamer
Handles emojitracker's SSE endpoints for streaming realtime updates to web clients.

Overall responsibilities:

 * Consumes all the PUBSUB update streams from Redis.
 * Implements a "score summarizer" pipeline, converting the primary `score_updates` stream from atomic updates (currently incoming at a typical rate of 250-400Hz) to rolled-up summary blobjects emitted at a maximum rate of 60Hz.
 * Accepts client connections on SSE endpoints
   - namespace connections based on request path resource IDs, allowing a client to subscribe to updates on arbitrary objects.
   - performs filter operations so that `detail` updates are only sent to SSE streams with interested clients connected.
   - multiplex all streams appropriately.

Additionally we must:
 * Periodically reports on status of the connection pools to the admin cluster.
 * Periodically log status of the connection pools to graphite.

### Legacy note

This represents the original version of emojitracker's SSE streaming functionality, being isolated into it's own service so that it can either be more easily improved or swapped out later.  It is being moved "as is" as much as possible for now.  Most importantly by moving this into it's own service we can horizontally scale streaming independently of the normal web frontend/API.

This version uses MRI Ruby threads for concurrency, but has EventMachine reactor stuff sprinkled in for timers and whatnot. (Told you it was a bit of a mess!)

Unlike the new experimental NodeJS version of emojitrack-streamer, this version still has the ability to manually manage client socket connections via `SSE_RECONNECT` timing, forced disconnects, and exposing AJAX endpoints for clients to manually indicate when they are done with a resource.  This enables it to work in environments where websocket-style connections are not natively supported (for example, behind Heroku's routing later if you don't have the websockets lab project enabled.)

## Streaming API
All endpoints are normal HTTP connections, which emit EventSource/SSE formatted data.

CORS headers are set to `*` so anyone can play, please don't abuse the privilege.

_Note to hackers: if you just want to get some data out of emojitracker and don't need to stream realtime data, you are probably looking for the [normal web API](#TODO)._

### Endpoints
#### `/subscribe/eps`

Emits a JSON blob every 17ms (1/60th of a second) containing the unicode IDs that have incremented and the amount they have incremented.

Example:

    data:{'1F4C2':2,'2665':3,'2664':1,'1F65C':1}

If there have been no updates in that period, in lieu of an empty array, no message will be sent.  Therefore, do not rely on this for timing data.

#### `/subscribe/details/:id`

Get every single tweet that pertains to the emoji glyph represented by the unified `id`.

Example:

    event:stream.tweet_updates.2665
    data:{"id":"451196288952844288","text":"유졍여신에게 화유니가아~♥\n햇살을 담은 my only one\n그대인거죠 선물같은 사람 달콤한 꿈속\n주인공처럼 영원히 with you♥\nAll about-멜로디데이\n@GAEBUL_Chicken ♥ @shy1189\n화윤애끼미랑평생행쇼할텨~?♥\n#화융자트","screen_name":"snowflake_Du","name":"잠수탄✻눈꽃두준✻☆글확인","links":[],"profile_image_url":"http://pbs.twimg.com/profile_images/437227370248806400/aP0fFJOk_normal.jpeg","created_at":"2014-04-02T03:15:52+00:00"}

*** More information to go here.

#### `/subscribe/raw`

*** Description.

This endpoint can be disabled in configuration.

## Developer setup
Instructions to go here.


## Other parts of emojitracker
This is but a small part of emojitracker's infrastructure.  Major components of the project include:

 - [emojitrack-web](http://github.com/mroth/emojitrack)
 - emojitrack-streamer
    * ruby version (current) {you are here!}
    * node version (experimental)
 - emojitrack-feeder

Many of the libraries emojitrack uses have also been carved out into independent open-source projects, see the following:

 - [emoji_data.rb](http://github.com/mroth/emoji_data.rb)
 - [emojistatic](http://github.com/mroth/emojistatic)

