Simple In Memory Channels
=========================

An Erlang Library that provides a simple API to create channels, channels support the following operations:

* start
* subscribe
* unsubscribe
* send
* stop

there's a channel that has "recent memory" and allows replaying from recently
seen events, the amount of history can be configured.

License
=======

MPL 2.0, see LICENSE
