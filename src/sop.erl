%%%-------------------------------------------------------------------
%%% @author Gary Hai <gary@XL59.com>
%%% @copyright (C) 2017, Neulinx Inc.
%%% @doc
%%%
%%% @end
%%% Created : 24 May 2017 by Gary Hai <gary@XL59.com>
%%%-------------------------------------------------------------------
-module(sop).

%% Support inline unit test for EUnit.
-ifdef(TEST).
    -include_lib("eunit/include/eunit.hrl").
-endif.


%%- APIs
%%------------------------------------------------------------------------------
%%-- Framework.
%% gen_server callbacks.
-behaviour(gen_server).
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3
        ]).

%% Launcher.
-export([start/1, start/2, start/3,
         start_link/1, start_link/2, start_link/3
        ]).
%% Creator.
-export([create/1, create/2,
         from_module/2
        ]).

%%-- Message helpers.
%% Generic.
-export([reply/2,
         call/2, call/3, call/4,
         cast/2, cast/3
        ]).

%% Operations.
-export([stop/1, stop/2,
         subscribe/1, subscribe/2,
         unsubscribe/2,
         notify/2
        ]).

%% Access.
-export([touch/1, touch/2,
         get/1, get/2,
         put/2, put/3,
         patch/2, patch/3,
         new/2, new/3,
         delete/1, delete/2
        ]).

%%-- Miscellanous.
%% Tags.
-export([timestamp/0,
         make_tag/0, make_tag/1,
         new_attribute/2
        ]).

%%-- Internal operations.
%% Path or sequence.
-export([chain/2,
         chain_action/3,
         chain_actions/3,
         chain_react/3,
         merge/2,
         swap/1
        ]).
%% Internal process.
-export([handle/2,
         invoke/3,
         attach/2, attach/3,
         detach/2
        ]).

%%-- Actions
-export([links/3,
         monitors/3,
         subscribers/3
        ]).


%%- MACROS
%%------------------------------------------------------------------------------
-define(DFL_TIMEOUT, 4000).
-define(DFL_MAX_STEPS, infinity).  % self-destructure as brute self-heal.

%%- Types.
%%------------------------------------------------------------------------------
%%-- Definitions for gen_server.
-type server_name() :: {local, atom()} |
                       {global, atom()} |
                       {via, atom(), term()} |
                       'undefined'.
-type start_ret() ::  {'ok', pid()} | 'ignore' | {'error', term()}.
-type start_opt() :: {'timeout', timeout()} |
                     {'spawn_opt', [proc_lib:spawn_option()]}.
%%-- state.
-type state() :: #{'entry' => entry_fun() | [entry_fun()],
                   'exit' => exit_fun() | [exit_fun()],
                   'do' => do_fun() | [do_fun()],
                   'pid' => pid(),
                   'entry_time' => timestamp(),
                   'exit_time' => timestamp(),
                   'status' => status(),
                   'timeout' => timeout(),
                   tag() => dynamic_attribute() | any()
                  }.

%%-- Attributes types.
-type dynamic_attribute() :: map() | function() | pid().
-type entry_fun() :: fun((state()) -> state()).
-type exit_fun() :: fun((state()) -> state()).
-type do_fun() :: fun((signal() | any(), state()) -> result()).
-type timestamp() :: integer().  % by unit of microseconds.
-type status() :: 'running' | tag().

%%-- Refined types.
-type tag() :: atom() | string() | binary() | integer() | tuple().
-type code() :: 'ok' | 'error' | 'noreply' | 'stop' |
                'stopping' | 'unhandled' | tag().
-type reply() :: code() | {code(), Result :: any()}.
-type result() :: {reply(), state()} |
                  {stop, Reason :: any(), state()} |
                  {stop, Reason :: any(), reply(), state()}.

%%-- Messages.
-type signal() :: {'$$', command()} |
                  {'$$', path(), command()} |
                  {'$$', from(), path(), command()}.
-type path() :: list() | tag().
-type from() :: {pid(), reference()} | 'call' | 'cast'.
-type command() :: method() | {method(), any()} | {'new', any(), any()} | any().
-type method() :: 'touch' |
                  'get' |
                  'put' |
                  'patch' |
                  'delete' |
                  'new' |
                  'stop' |
                  tag().
-type process() :: pid() | atom().
-type target() :: process() | path().

%%-- actors
-type actor_type() :: 'stem' | 'actor' | 'fsm' | 'thing'.

%%- Starts the server
%%------------------------------------------------------------------------------
-spec start_link(state()) -> start_ret().
start_link(State) ->
    start_link(State, []).

-spec start_link(state(), [start_opt()]) -> start_ret().
start_link(State, Options) ->
    Opts = merge_options(Options, State),
    gen_server:start_link(?MODULE, State, Opts).

-spec start_link(server_name(), state(), [start_opt()]) -> start_ret().
start_link(undefined, State, Options) ->
    start_link(State, Options);
start_link(Name, State, Options) ->
    Opts = merge_options(Options, State),
    gen_server:start_link(Name, ?MODULE, State, Opts).

-spec start(state()) -> start_ret().
start(State) ->
    start(State, []).

-spec start(state(), [start_opt()]) -> start_ret().
start(State, Options) ->
    Opts = merge_options(Options, State),
    gen_server:start(?MODULE, State, Opts).

-spec start(server_name(), state(), [start_opt()]) -> start_ret().
start(undefined, State, Options) ->
    start(State, Options);
start(Name, State, Options) ->
    Opts = merge_options(Options, State),
    gen_server:start(Name, ?MODULE, State, Opts).

%% If option {timeout,Time} is present, the gen_server process is allowed to
%% spend $Time milliseconds initializing or it is terminated and the start
%% function returns {error,timeout}.
merge_options(Options, State) ->
    case proplists:is_defined(timeout, Options) of
        true ->
            Options;
        false ->
            Timeout = maps:get(timeout, State, ?DFL_TIMEOUT),
            Options ++ [{timeout, Timeout}]
    end.

-spec create(actor_type()) -> state().
create(Type) ->
    create(Type, #{}).

-spec create(actor_type() | module(), map()) -> state().
%% stem: state().
create(stem, Data) ->
    Data;
%% fsm: stem, $start, $state, $fsm, states, step, max_steps, sign, payload.
create(fsm, Data) ->
    chain_action(Data, do, fun fsm_do/2);
%% actor: stem, subscribers, _subscribers, links, _links, monitors, _monitors,
%% report_items, surname, parent.
create(actor, Data) ->
    Actor = #{subscribers => fun subscribers/3,
              links => fun links/3,
              monitors => fun monitors/3,
              do => fun actor_do/2,
              exit => fun actor_exit/1
             },
    merge(Actor, Data);
%% thing: stem, fsm, actor.
create(thing, Data) ->
    Thing = #{subscribers => fun subscribers/3,
              links => fun links/3,
              monitors => fun monitors/3,
              do => [fun fsm_do/2, fun actor_do/2],
              exit => fun actor_exit/1
             },
    merge(Thing, Data);
create(Module, Data) ->
    from_module(Module, Data).

-spec from_module(module(), map()) -> state().
from_module(Module, Data) ->
    case erlang:function_exported(Module, create, 1) of
        true ->
            Module:create(Data);
        _ ->
            A1 = case erlang:function_exported(Module, entry, 1) of
                     true->
                         chain_action(Data, entry, fun Module:entry/1);
                     false ->
                         Data
                 end,
            A2 = case erlang:function_exported(Module, do, 2) of
                     true->
                         chain_action(A1, do, fun Module:do/2);
                     false ->
                         A1
                 end,
            case erlang:function_exported(Module, exit, 1) of
                true->
                    chain_action(A2, exit, fun Module:exit/1);
                false ->
                    A2
            end
    end.

-spec merge(state(), state()) -> state().
merge(State1, State2) ->
    State3 = chain_actions(State2, State1, [entry, do, exit]),
    maps:merge(State1, State3).

%% gen_server callbacks
%%------------------------------------------------------------------------------
%% Initializes the server
%% -callback init(Args :: term()) ->
%%     {ok, State :: term()} | {ok, State :: term(), timeout() | hibernate} |
%%     {stop, Reason :: term()} | ignore.
init(#{status := running} = State) ->
    process_flag(trap_exit, true),
    self() ! '$$resume',
    {ok, State};
init(State) ->
    process_flag(trap_exit, true),
    self() ! '$$enter',
    S0 = #{entry_time => timestamp(),
           pid => self(),
           status => running,
           timeout => ?DFL_TIMEOUT},
    S1 = maps:merge(S0, State),
    %% try...catch for gen_server cleanup.
    try
        {ok, on_entry(S1)}
    catch
        throw: Reason ->
            {stop, Reason};
        exit: Reason ->
            {stop, Reason};
        error: Error ->
            {stop, {error, Error}}
    end.

%% Handling sync call messages.
%% 
%% -callback handle_call(Request :: term(), From :: {pid(), Tag :: term()},
%%                       State :: term()) ->
%%     {reply, Reply :: term(), NewState :: term()} |
%%     {reply, Reply :: term(), NewState :: term(), timeout() | hibernate} |
%%     {noreply, NewState :: term()} |
%%     {noreply, NewState :: term(), timeout() | hibernate} |
%%     {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
%%     {stop, Reason :: term(), NewState :: term()}.
handle_call({To, Method, Args}, From, State) ->
    handle_info({'$$', From, To, {Method, Args}}, State);
handle_call({To, Method}, From, State) ->
    handle_info({'$$', From, To, Method}, State);
handle_call(Method, From, State) ->
    handle_info({'$$', From, [], Method}, State).


%% Handling async cast messages.
%% 
%% -callback handle_cast(Request :: term(), State :: term()) ->
%%     {noreply, NewState :: term()} |
%%     {noreply, NewState :: term(), timeout() | hibernate} |
%%     {stop, Reason :: term(), NewState :: term()}.
handle_cast({To, Method, Args}, State) ->
    handle_info({'$$', cast, To, {Method, Args}}, State);
handle_cast({To, Method}, State) ->
    handle_info({'$$', cast, To, Method}, State);
handle_cast(Method, State) ->
    handle_info({'$$', cast, [], Method}, State).

%% Handling normal messages.
%% 
%% -callback handle_info(Info :: timeout | term(), State :: term()) ->
%%     {noreply, NewState :: term()} |
%%     {noreply, NewState :: term(), timeout() | hibernate} |
%%     {stop, Reason :: term(), NewState :: term()}.
handle_info(Info, State) ->
    case chain_react(do, Info, State) of
        {unhandled, S} ->
            handle(Info, S);
        Result ->
            Result
    end.

%% This function is called by a gen_server when it is about to terminate. It
%% should be the opposite of Module:init/1 and do any necessary cleaning
%% up. When it returns, the gen_server terminates with Reason. The return value
%% is ignored.
%% 
%% -callback terminate(Reason :: (normal | shutdown | {shutdown, term()} |
%%                                term()),
%%                     State :: term()) ->
%%     term().

terminate(Reason, State) ->
    on_exit(State#{reason => Reason, exit_time => timestamp()}).

%% Convert process state when code is changed
%%
%% -callback code_change(OldVsn :: (term() | {down, term()}), State :: term(),
%%                       Extra :: term()) ->
%%     {ok, NewState :: term()} | {error, Reason :: term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%- Message processing.
%%------------------------------------------------------------------------------
-spec reply({tag(), reference()}, Reply :: any()) -> 'ok'.
reply({To, Tag}, Reply) ->
    catch To ! {Tag, Reply},
    ok;
reply(_, _) ->
    ok.

-spec call(target(), Request :: any()) -> reply().
call([Process | Path], Command) ->
    call(Process, Path, Command, ?DFL_TIMEOUT);
call(Process, Command) ->
    call(Process, [], Command, ?DFL_TIMEOUT).

-spec call(target(), Request :: any(), timeout()) -> reply().
call([Process | Path], Command, Timeout) ->
    call(Process, Path, Command, Timeout);
call(Process, Command, Timeout) ->
    call(Process, [], Command, Timeout).

-spec call(process(), path(), Request :: any(), timeout()) -> reply().
call(Process, Path, Command, Timeout) ->
    Mref = monitor(process, Process),
    Tag = make_ref(),
    Process ! {'$$', {self(), Tag}, Path, Command},
    receive
        {Tag, Result} ->
            demonitor(Mref, [flush]),
            Result;
        {'DOWN', Mref, _, _, Reason} ->
            {stopped, Reason}
    after
        Timeout ->
            demonitor(Mref, [flush]),
            {error, timeout}
    end.

-spec cast(target(), Message :: any()) -> 'ok'.
cast([Process | Path], Command) ->
    cast(Process, Path, Command);
cast(Process, Command) ->
    cast(Process, [], Command).

-spec cast(process(), path(), Message :: any()) -> 'ok'.
cast(Process, Path, Message) ->
    catch Process ! {'$$', cast, Path, Message},
    ok.

%%-- Data access.
%%------------------------------------------------------------------------------
%% To check existence of an attribute. Return summary of the attribute or
%% {error, undefined} if it is not existed.
-spec touch(path()) -> reply().
touch(Path) ->
    call(Path, touch).

-spec touch(path(), Options :: any()) -> reply().
touch(Path, Options) ->
    call(Path, {touch, Options}).

-spec get(path()) -> reply().
get(Path) ->
    call(Path, get).

-spec get(path(), Options :: any()) -> reply().
get(Path, Options) ->
    call(Path, {get, Options}).

-spec put(path(), Value :: any()) -> reply().
put(Path, Value) ->
    call(Path, {put, Value}).

-spec put(path(), Value :: any(), Options :: any()) -> reply().
put(Path, Value, Options) ->
    call(Path, {put, Value, Options}).

-spec patch(path(), Value :: any()) -> reply().
patch(Path, Value) ->
    call(Path, {patch, Value}).

-spec patch(path(), Value :: any(), Options :: any()) -> reply().
patch(Path, Value, Options) ->
    call(Path, {patch, Value, Options}).

-spec new(path(), Value :: any()) -> reply().
new(Path, Value) ->
    call(Path, {new, Value}).

-spec new(path(), tag(), Value :: any()) -> reply().
new(Path, Key, Value) ->
    call(Path, {new, Key, Value}).

-spec delete(path()) -> reply().
delete(Path) ->
    call(Path, delete).

-spec delete(path(), Options :: any()) -> reply().
delete(Path, Options) ->
    call(Path, {delete, Options}).

%%-- Operations.
%%------------------------------------------------------------------------------
-spec subscribe(path()) -> reply().
subscribe(Path) ->
    Target = chain(Path, subscribers),
    call(Target, {new, self()}).

-spec subscribe(path(), pid()) -> reply().
subscribe(Path, Pid) ->
    Target = chain(Path, subscribers),
    call(Target, {new, Pid}).

-spec unsubscribe(path(), reference()) -> reply().
unsubscribe(Path, Ref) ->
    Target = chain(Path, [subscribers, Ref]),
    call(Target, delete).

-spec notify(path(), Info :: any()) -> reply().
notify(Path, Info) ->
    Target = chain(Path, subscribers),
    call(Target, {notify, Info}).

-spec stop(target()) -> reply().
stop(Path) ->
    call(Path, stop).

-spec stop(target(), Reason :: any()) -> reply().
stop(Path, Reason) ->
    call(Path, {stop, Reason}).

%%- Miscellaneous
%%------------------------------------------------------------------------------
-spec timestamp() -> integer().
timestamp() ->
    erlang:system_time(micro_seconds).

-spec make_tag() -> binary().
make_tag() ->
    make_tag(8).

-spec make_tag(pos_integer()) -> binary().
make_tag(N) ->
    B = base64:encode(crypto:strong_rand_bytes(N)),
    binary_part(B, 0, N).

-spec new_attribute(Value :: any(), map()) -> {tag(), map()}.
new_attribute(Value, Map) ->
    Key = make_tag(),
    case maps:is_key(Key, Map) of
        true ->
            new_attribute(Value, Map);
        false ->
            {Key, Map#{Key => Value}}
    end.

-spec chain_action(state(), tag(), function() | list()) -> state().
chain_action(State, Name, Func) ->
    case maps:find(Name, State) of
        error ->
            State#{Name => Func};
        {ok, F} ->
            State#{Name := chain(F, Func)}
    end.

-spec chain_actions(state(), state(), [tag()]) -> state().
chain_actions(State1, State2, Actions) ->
    Func = fun(Key, State) ->
                   case maps:find(Key, State2) of
                       {ok, Value} ->
                           chain_action(State, Key, Value);
                       error ->
                           State
                   end
           end,
    lists:foldl(Func, State1, Actions).

-spec chain(Head :: any(), Tail :: any()) -> list().
chain(Head, Tail) when is_list(Head) andalso is_list(Tail) ->
    Head ++ Tail;
chain(Head, Tail) when is_list(Head) ->
    Head ++ [Tail];
chain(Head, Tail) when is_list(Tail) ->
    [Head | Tail];
chain(Head, Tail) ->
    [Head, Tail].

-spec chain_react(tag(), Event :: any(), state()) -> result().
chain_react(Attribute, Event, State) ->
    case maps:find(Attribute, State) of
        error ->
            {unhandled, State};
        {ok, Func} when is_function(Func) ->
            Func(Event, State);
        {ok, Stack} when is_list(Stack) ->
            on_event(Stack, Event, State)
    end.

%%-- sop messages.
-spec handle(Command :: any(), state()) -> result().
handle({'$$', From, To, Command}, State) ->
    response(From, request(Command, To, From, State));
handle({'$$', From, Command}, State) ->
    response(From, request(Command, [], From, State));
handle({'$$', Command}, State) ->
    response(cast, request(Command, [], cast, State));
%% Drop unknown messages. Nothing replied.
handle(_, State) ->
    {noreply, State}.

%%- Internal state operation.
-spec invoke(Command :: any(), path(), state()) -> result().
invoke(Command, Path, State) ->
    case access(Command, Path, State) of
        {result, Res} ->
            {Res, State};
        {update, Reply, NewState} ->
            {Reply, NewState};
        {action, Func, Route} ->
            perform(Func, Command, Route, call, State);
        {actor, Pid, Sprig} ->
            Tag = make_ref(),
            Pid ! {'$$', {self(), Tag}, Sprig, Command},
            Timeout = maps:get(timeout, State, ?DFL_TIMEOUT),
            receive
                {Tag, Result} ->
                    {Result, State}
            after
                Timeout ->
                    {{error, timeout}, State}
            end;
        {delete, ok} ->
            {{error, badarg}, State}
    end.

-spec attach(tag(), state()) -> result().
attach(Key, State) ->
    {_, S} = detach(Key, State),
    Path = chain('_links', Key),
    case invoke(get, Path, S) of
        {{ok, Value}, S1} ->
            attach(Key, Value, S1);
        Error ->
            Error
    end.

-spec attach(tag(), Value :: any(), state()) -> result().
attach(Key, Pid, State) when is_pid(Pid) ->
    %% Ignore result of monitors.
    case invoke({new, Key, Pid}, [monitors], State) of
        {_, S} ->
            {ok, S#{Key => Pid}};
        Stop ->
            Stop
    end;
attach(Key, {state, S}, State) ->
    S1 = S#{surname => Key, parent => self()},
    case start_link(S1) of
        {ok, Pid} ->
            case invoke({new, Key, Pid}, [monitors], State) of
                {_, State1} ->
                    {ok, State1#{Key => Pid}};
                Stop ->
                    Stop
            end;
        Error ->
            {Error, S1}
    end;
%% To accept pid or state data.
attach(Key, {data, Value}, State) ->
    {ok, State#{Key => Value}};
attach(Key, Value, State) ->
    {ok, State#{Key => Value}}.

-spec detach(tag(), state()) -> result().
detach(Key, State) ->
    case invoke({delete, Key}, [monitors], State) of
        {_, S} ->
            {ok, maps:remove(Key, S)};
        Stop ->
            Stop
    end.

-spec swap(state()) -> state().
swap(#{'$state' := S} = Fsm) ->
    S#{'$fsm' => maps:remove('$state', Fsm)};
swap(#{'$fsm' := F} = State) ->
    F#{'$state' => maps:remove('$fsm', State)}.

%%- Active attributes.
%%------------------------------------------------------------------------------
%%-- Subscription & notification.
%% Introduced:
%%  * 'subscribers': active attribute for subscription actions.
%%  * '_subscribers': subscribers data cache.
%%  * 'report_items': definition of output items when actor exit.
-spec subscribers(Command :: any(), path(), state()) -> result().
subscribers({new, Pid}, [], State) ->
    Subs = maps:get('_subscribers', State, #{}),
    Mref = monitor(process, Pid),
    Subs1 = Subs#{Mref => Pid},
    {ok, Mref, State#{'_subscribers' => Subs1}};
subscribers(delete, [Mref], #{'_subscribers' := Subs} = State) ->
    demonitor(Mref),
    Subs1 = maps:remove(Mref, Subs),
    {ok, State#{'_subscribers' := Subs1}};
subscribers({notify, Info}, [], #{'_subscribers' := Subs} = State) ->
    maps:fold(fun(M, P, _) -> catch P ! {M, Info} end, 0, Subs),
    {ok, State};
subscribers({notify, Info, remove}, [], #{'_subscribers' := Subs} = State) ->
    maps:fold(fun(Mref, Pid, _) ->
                      catch Pid ! {Mref, Info},
                      demonitor(Mref)
              end, 0, Subs),
    {ok, maps:remove('_subscribers', State)};
subscribers(_, _, State) ->
    {{error, badarg}, State}.

%%-- Links
-spec links(Command :: any(), path(), state()) -> result().
links(touch, Key, State) ->
    attach(Key, State);
links(get, Key, State) ->
    case attach(Key, State) of
        {ok, S} ->
            {ok, maps:get(Key, S), S};
        Error ->
            Error
    end;
links({new, Target}, Key, State) ->
    Path = chain('_links', Key),
    case invoke({new, Target}, Path, State) of
        {ok, S} ->
            attach(Key, S);
        Error ->
            Error
    end;
links(delete, Key, State) ->
    detach(Key, State);
links(_, _, State) ->
    {{error, badarg}, State}.

-spec monitors(Command :: any(), path(), state()) -> result().
monitors({get, Key}, [], #{'_monitors' := M} = State) ->
    case maps:find(Key, M) of
        error ->
            {{error, undefined}, State};
        Ok ->
            {Ok, State}
    end;
monitors({new, Key, Pid}, [], State) ->
    M = maps:get('_monitors', State, #{}),
    Mref = monitor(process, Pid),
    M1 = M#{Mref => Key, Key => Mref},
    {{ok, Mref}, State#{'_monitors' => M1}};
monitors({delete, all}, [], #{'_monitors' := M} = State) ->
    maps:fold(fun(Mref, _, _) when is_reference(Mref) ->
                      demonitor(Mref);
                 (_, _, _) ->
                      noop
              end, 0, M),
    maps:remove('_monitors', State);
monitors({delete, Key}, [], #{'_monitors' := M} = State) ->
    case maps:find(Key, M) of
        {ok, Ref} when is_reference(Ref) ->
            demonitor(Ref),
            M1 = maps:remove(Key, M),
            M2 = maps:remove(Ref, M1),
            {{ok, Ref}, State#{'_monitors' := M2}};
        {ok, Ref} when is_reference(Key) ->
            demonitor(Key),
            M1 = maps:remove(Key, M),
            M2 = maps:remove(Ref, M1),
            {{ok, Ref}, State#{'_monitors' := M2}};
        error ->
            {{error, undefined}, State}
    end;
monitors(get, [Key], State) ->
    monitors({get, Key}, [], State);
monitors({new, Pid}, [Key], State) ->
    monitors({new, Key, Pid}, [], State);
monitors(delete, [Key], State) ->
    monitors({delete, Key}, [], State);
monitors(_, _, State) ->
    {{error, badarg}, State}.

%%!todo: support {proxy, target()} | {proxy, {pid(), path()}}.
actor_do({'$$', From, [Key | _], _} = Req, State) ->
    case maps:find(Key, State) of
        error ->
            case invoke(touch, [states, Key], State) of
                {ok, S} ->
                    handle(Req, S);
                {Error, S} ->
                    reply(From, Error),
                    {noreply, S};
                Stop ->
                    Stop
            end;
        _ ->
            handle(Req, State)
    end;
actor_do({'DOWN', M, _, _, _}, State) ->
    S = case maps:find('_subscribers', State) of
            {ok, Subs} ->
                Subs1 = maps:remove(M, Subs),
                State#{'_subscribers' := Subs1};
            error ->
                State
        end,
    case invoke({delete, M}, [monitors], S) of
        {{ok, Key}, S1} ->
            {ok, maps:remove(Key, S1)};
        {_, State} ->  % no change
            {unhandled, State};
        {_, S1} ->
            {noreply, S1};
        Stop ->
            Stop
    end;
actor_do(_, State) ->
    {unhandled, State}.

%% Goodbye, subscribers! And submit leave report.
actor_exit(State) ->
    Detail = maps:get('report_items', State, []),
    Report = make_report(Detail, State),
    Info = {exit, Report},
    {_, S} = invoke({notify, Info, remove}, [subscribers], State),
    {_, S1} = invoke({delete, all}, [monitors], S),
    S1.

%% If $state is present before FSM start, it is an introducer for flexible
%% initialization.
fsm_do(Info, #{'$state' := _} = Fsm) ->
    do_state(Info, swap(Fsm));
fsm_do('$$enter', #{'$start' := Start} = Fsm) ->
    transition(Start, Fsm);
fsm_do(_, Fsm) ->
    {unhandled, Fsm}.


%%- Internal functions.
%%------------------------------------------------------------------------------
on_entry(#{entry := Entry} = State) when is_function(Entry) ->
    Entry(State);
on_entry(#{entry := Entry} = State) ->
    lists:foldl(fun(F, S) -> F(S) end,
                State,
                Entry);
on_entry(State) ->
    State.

on_exit(#{exit := Exit} = State) when is_function(Exit) ->
    Exit(State);
on_exit(#{exit := Exit} = State) ->
    lists:foldl(fun(F, S) ->
                        try
                            F(S)
                        catch
                            _:_ -> S
                        end
                end,
                State,
                Exit);
on_exit(State) ->
    State.

on_event([Do | Rest], Info, State) ->
    case Do(Info, State) of
        {unhandled, S} ->
            on_event(Rest, Info, S);
        Handled ->
            Handled
    end;
on_event([], _, State) ->
    {unhandled, State}.

%%-- Reply and normalize result of request.
response(_, {noreply, NewState}) ->
    {noreply, NewState};
response(Caller, {Reply, NewState}) ->
    reply(Caller, Reply),
    {noreply, NewState};
response(Caller, {stop, Reason, NewState}) ->
    reply(Caller, stopping),
    {stop, Reason, NewState};
response(Caller, {stop, Reason, Reply, NewState}) ->
    reply(Caller, Reply),
    {stop, Reason, NewState}.

%% Invoke on root of actor.
request(stop, [], _, State) ->
    {stop, normal, State};
request({stop, Reason}, [], _, State) ->
    {stop, Reason, State};
request(Command, [], _, State) ->
    case access(Command, [], State) of
        {result, Res} ->
            {Res, State};
        {update, Reply, NewS} when (not is_tuple(Command));
                                   element(1, Command) =/= put ->
            {Reply, NewS};
        _ ->
            {{error, badarg}, State}
    end;
%% Branches and sprig.
request(Command, To, From, State) ->
    case access(Command, To, State) of
        {result, Res} ->
            {Res, State};
        {update, Reply, NewState} ->
            {Reply, NewState};
        {action, Func, Route} ->
            perform(Func, Command, Route, From, State);
        {actor, Pid, Sprig} ->
            catch Pid ! {'$$', From, Sprig, Command},
            {noreply, State}
    end.

access(touch, [], _) ->
    {result, ok};
access(get, [], Data) ->
    {result, {ok, Data}};
access({put, Value}, [], _) ->
    {update, ok, Value};
access(delete, [], _) ->
    {delete, ok};
access({touch, Selection}, [], Data) ->
    access({get, Selection}, [], Data);
access({get, Selection}, [], Data)
  when is_list(Selection) andalso is_map(Data) ->
    Value = maps:with(Selection, Data),
    {result, {ok, Value}};
access({patch, Value}, [], Data)
  when is_map(Value) andalso is_map(Data) ->
    NewData = maps:merge(Data, Value),
    {update, ok, NewData};
access({new, Key, Value}, [], Data) when is_map(Data) ->
    {update, ok, Data#{Key => Value}};
access({new, Value}, [], Data) when is_map(Data) ->
    {Key, NewData} = new_attribute(Value, Data),
    {update, {ok, Key}, NewData};
access(Command, [Key | Rest], Data) when is_map(Data) ->
    case maps:find(Key, Data) of
        {ok, Value} ->
            case access(Command, Rest, Value) of
                {update, Reply, NewValue} ->
                    {update, Reply, Data#{Key => NewValue}};
                {delete, Reply} ->
                    {update, Reply, maps:remove(Key, Data)};
                Result ->
                    Result
            end;
        error ->
            {result, {error, undefined}}
    end;
access(_, Sprig, Data) when is_function(Data) ->
    {action, Data, Sprig};
access(_, Sprig, Data) when is_pid(Data) ->
    {actor, Data, Sprig};
access(_, [], _) ->
    {result, {error, badarg}};
access(Command, Key, State) ->
    access(Command, [Key], State).

perform(Func, Command, _, _, State) when is_function(Func, 2) ->
    Func(Command, State);
perform(Func, Command, Sprig, _, State) when is_function(Func, 3) ->
    Func(Command, Sprig, State);
perform(Func, Command, Sprig, From, State) ->
    Func(Command, Sprig, From, State).

%% Selective report.
make_report(all, State) ->
    State;
%% Selections is a list of attributes to yield.
make_report(Selections, State) when is_list(Selections) ->
    maps:with(Selections, State).

%%!todo: archive historic states as traces.
%%        {_, F1} = invoke({new, Fsm}, [traces], Fsm),            
transition(Sign, Fsm) ->
    Step = maps:get(step, Fsm, 0),
    F1 = Fsm#{step => Step + 1},
    %% states should handle exceptions. For examples: vertex of sign is not
    %% found or exceed max steps limited.
    case invoke(get, [states, Sign], F1) of
        {{ok, State}, F2} ->
            enter_state(F2#{'$state' => State});
        {Error, F2} ->
            {stop, Error, F2};
        Stop ->
            Stop
    end.

enter_state(#{step := Step, max_steps := Max} = Fsm) when Step >= Max ->
    {stop, {shutdown, exceed_max_steps}, Fsm};
enter_state(Fsm) ->
    try
        S = on_entry(swap(Fsm)),
        do_state('$$enter', S)
    catch
        C : E ->
            transition(exception, Fsm#{payload => {C, E}})
    end.

%%!todo: {stop, {transition, NewState}, State}, be free & evil.
do_state(Info, State) ->
    case handle_info(Info, State) of
        {Result, S} ->
            {Result, swap(S)};
        {stop, normal, S} ->
            try
                S1 = on_exit(S),
                Sign = maps:get(sign, S1, stop),
                transition(Sign, swap(S1))
            catch
                C : E ->
                    Fsm = swap(S),
                    transition(exception, Fsm#{payload => {C, E}})
            end;
        {stop, Shutdown, S} ->
            {stop, Shutdown, swap(S)}
    end.
