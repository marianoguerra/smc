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

Test
----

::

    ./rebar compile ct

to play with the property based tests done with triq, run::

    ./rebar compile shell

and inside::

    triq:check(smc_triq:smc_statem()).

to run more tests::

    triq:check(smc_triq:smc_statem(), 10000).

License
=======

MPL 2.0, see LICENSE
