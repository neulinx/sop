CHANGELOG
=========

v2.12.1, re-export cast/4 and bump the version for new release.
---------------------------------------------------------------

- Export `fun cast/4`.

v2.12.0, simplify the exported functions for asynchronous call.
---------------------------------------------------------------

- Merge 'relay' functions to 'cast' function.
- Remove `asyn_call`, be replaced by 'cast'.
- Change `invoke/5` to `invoke/4` and simplify it.

v2.11.0, refactor the asynchronous call mechanism.
-------------------------------------------------

- Change behavior of asyn_call functions.
- Change behavior of callback functions.
- Improve reply functions to support async call.
- Remove old fashion of asynchoronous call.
- invoke functions have two version: sync and async.

v2.10.0, asynchronous callback and quit process anywhere.
---------------------------------------------------------

- To quit process with updated state by call `exit({stop, Reason, State})`,
  which simplify the result process by ignore case of stop.
- Fix a minor bug of duplicated reply when invoke stop command.
- External reason of quit (by external command or link break) is format of
  `{shutdown, Reason}`.
- Simplify the asynchronous callback without chain call support.
- Fix bug of overlapped "asyn_call".


v2.9.0, change internal name of attribute `links` to `props`.
-------------------------------------------------------------

- Change 'stem' template name to 'prop'.
- Simplify logic of `props_do`.
- Remove priority of `props` access in FSM.

v2.8.0, finite state machine, unit test passed.
----------------------------------------------

- Fix bug of bonds.
- Default timeout value of function call changed to `infinity`.
- Remove `_do` callback.
- Change `$start` to `start` and make it as start event of FSM and thing.
- Remove call/4, cast/3.
- create/2 function is enhanced by enable/2 function.
- create from module now support all attributes and exported functions of the
  module.
- Seperate functionalities of thing, such as link, monitor, subscribe.
- Now fsm support notifications.
- Export template() type.
- Fix bug of `chain_action` Position parameter.
- Fix bug of state transition notify.
- Add syntex sugar of FSM state action.
- Change the order of fsm and thing behaviors, move fsm_do the the tail.

v2.7.0, enhance asyn_call function.
----------------------------------

- Remove unused exported functions.
- Add relay function to forward request to another actor.
- Add factory support in create function.
- `asyn_call` support sticky mode.
- Callback function of `asyn_call` return `{pending, S}`/`{done, S}`.

v2.6.2, avoid confusion of 'get', 'put', 'delete' actions.
----------------------------------------------------------

- fun invoke/3 support {refer, Target, Command, State} format result.
- When options of get, put, delete is 'raw', operate the raw data of attribute
  value directly.

v2.6.1, change `relay` to `refer`.
----------------------------------

- Spell of `relay` is too close to `reply`. 
- Now support result format of {refer, Target, NewCommand, State} to alert
  request data.

v2.6.0, add bonds as fatal links support.
-----------------------------------------

- Simplify launcher of start functions.
  - Only start/1 left.
  - Add `run_mode`, `register_name`, `start_options`.
  - Remove `actor_entry/1` action.
- Add bonds attribute for fatal links.
- Add helpers for bonds operation.
- `detach/2` return attribute value now.

v2.5.2, actor add work_mode.
----------------------------

- Do not export actions.
- Add actor_entry to monitor parent.
- Unified monitor, do not support link.

v2.5.1, merge bonds to monitors.
--------------------------------

And re-arrange code blocks of sop.erl to ease reading and testing.

2.5.0 bonds of actors
---------------------

- Fix minor issue of asyn_call cleanup: try demonitor anyway.
- Add `bonds` attribute to implement links of processes.

2.4.0 Internal call support asynchronous mode
---------------------------------------------

- Add fun act/2 helper.
- Make chain_action more gerenic, and support chain position.
- Asynchronous call support:
  - `chain_callback`, `enqueue_callback`, `asyn_call`
  - `handle_result` add to handle procedure to check and invoke callback queue.
  - Check `DOWN` message to cleanup pending_queue of callbacks.
- Remoe fun links/3 function.
- Change coding style.
  - Two blank lines between code segments.
  - Group functions by relevance rather than internal/external.

2.3.0 Many features added and passed first unit test
----------------------------------------------------

- Fix bug of links cache access.
- Do not auto import erlang:get/1 and erlang:put/2.
- Merge `state` and `_state` attribute and remove state function.
  - And make attach/2 more specified for active attribute.
- Change name of proxy to relay, which is to distingush from `asyn_call`.
- Export `relay/4` and `state_call/4`.
- Change function specs parameters `Command :: any()` to `command()`.
- Split `actor_do` into `links_do`, `monitors_do` and `subscribers_do`.
- Re-export `links`, `monitors`, `subscribers`, `links_do`, `monitors_do`,
  `subscibers_do`.
- Add helper function act/3, for differenct wrap for request.
- Make root action more custmoized, '_do' function for global command.
- Export access/3, perform/5.

2.2.2 Support message path which is not list type
------------------------------------------------

- `{'$$', Caller, Target, Command}`, which Target can be any type.

2.2.1 Change request format of action new
-----------------------------------------

- API new/3: from new(Path, Key Value) to new(Path, Value, Options).
- Action new: from {new, Key, Value} to {new, Value, #{key := Key}}.

2.2.0 New feature: proxy
------------------------

- `do` function may return {proxy, Pid, State}, means redirect current command
  to other actor process.
- Active attribute may return {proxy, Target, State}, means refer to other
  attribute in the same actor or redirect to another actor attribute.

2.1.1 Simplify reply and result format
--------------------------------------

- reply format of {ok, Result} is simplified to Result.

2.1.0 stem, fsm, actor and thing
--------------------------------

Updated version. But it is not stable version.

- Remove `chain_action/4` and add `chain_actions/3`.
- Fix dialyzer warning of state actions.
- Creator now support stem, fsm, actor and thing.
- Simplify merge/2 function with cost of `chain_actions`.
- Simplify fsm behavior and finish it.

2017-7-5 Unfinished FSM behaviors
---------------------------------

- Make '$' as sop special flag or prefix.
  - '$$' as sop message flag.
  - '$enter' as state enter event.
  - '$resume' as state resume or wakeup event.
- When create actor, give priority to initial data to supersede attributes.
- Add swap function for FSM/State switching.


2017-7-4 Actor
--------------

- Add {new, Value} command. Generate unique attribute name and return it.
- `new` request with key name reponse only `ok`.
- Export `timestamp/0, make_tag/0, make_tag/1, new_attribute/2`.
- `make reset` don't remove rebar.lock file.
- Add helper functions for common messages.
  - call, cast, stop.
  - touch, get, put, patch, new, delete.
- Add subscribers attribute and helpers.
  - subscribe
  - unsubscribe
  - notify
- Add links attribute and helpers.
  - link
  - unlink
- Add monitors attribute.
- Add internal operation functions for actor.
  - `chain`, `chain_action`, `chain_react`
  - `invoke`, `attach`, `detach`
- Change result format.
  - Non-stop message form should be {reply(), state()}.
  - Error message should be {{error, Error}, state()}.
- Export merge/2 function to combine two states of actors.


2.0.0 Generic actor with maximum flexibility
--------------------------------------------

- Add {new, Value} command. Generate unique attribute name and return it.
- `new` request with key name reponse only `ok`.
- Export `timestamp/0, make_tag/0, make_tag/1, new_attribute/2`.
- `make reset` don't remove rebar.lock file.
- Add helper functions for common messages.
  - call, cast, stop.
  - touch, get, put, patch, new, delete.
- Add subscribers attribute and helpers.
  - subscribe
  - unsubscribe
  - notify
- Add links attribute and helpers.
  - link
  - unlink
- Add monitors attribute.
- Add internal operation functions for actor.
  - `chain`, `chain_action`, `chain_react`
  - `invoke`, `attach`, `detach`
- Change result format.
  - Non-stop message form should be {reply(), state()}.
  - Error message should be {{error, Error}, state()}.
- Export merge/2 function to combine two states of actors.


2.0.0
-----

- Skip 1.x.x version scheme to keep for xl_sop project.
- Support attribute tree traverse.
- Message format & protocol:
  - `gen_server:call(Signal, From, State)`
    - Signal: `{To, Method, Args} | {To, Method} | Method`.
    - Convert to `{sos, From, To, {Method, Args}}`.
  - Message: `{sos, From, To, Command}`.
- function() & pid() types of attributes as dynamic attribute.
- Attribute function suport fun/2, fun/3, fun/4.
  - Func(Command, State)
  - Func(Command, Sprig, State)
  - Func(Command, Sprig, Via, State)
- Add `entry_time` attribute at startup of actor process.
- Add `exit_time` attribute when actor terminated.
- Add entry/exit/do behaviors of classic state.
- Use new data type map() as internal data of stata.
- Add more starting APIs.
- Apply new style of comment lines.
- rebar3, v3.4.1
- Makefile commands: all, devel, compile, dialyzer, unlock, cover, shell, reset,
  test, clean.
- Erlang/OTP 19 Erts 8.3
- gen_server framework generated by Erlang mode for Emacs.