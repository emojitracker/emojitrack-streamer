# emojitrack
emojitrack tracks realtime emoji usage on twitter! it takes advantage of a number of technologies, notably the twitter streaming API, redis, SSE, and other good stuff.

## emojitrack-streamer-rb
description here

legacy

Unlike the node version of emojitrack-streamer, this version has the ability to manually manage client socket connections via SSE_RECONNECT timing, forced disconnects, and exposing AJAX endpoints for clients to manually indicate when they are done with a resource.  This enables it to work in environments where websocket-style connections are not natively supported (for example, behind Heroku's routing later if you don't have the websockets lab project enabled.)

## other parts of emojitrack
Note: many of the components emojitrack uses have been carved out into independent open-source projects, see the following:

 - [emoji_data.rb](http://github.com/mroth/emoji_data.rb)
 - [emojistatic](http://github.com/mroth/emojistatic)

TODO fill out

## setup
## API
