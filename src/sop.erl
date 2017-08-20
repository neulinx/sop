%%%-------------------------------------------------------------------
%%% @author Gary Hai <gary@XL59.com>
%%% @copyright (C) 2017, Neulinx Inc.
%%% @doc
%%%
%%% @end
%%% Created : 24 May 2017 by Gary Hai <gary@XL59.com>
%%%-------------------------------------------------------------------
-module(sop).

-compile({no_auto_import, [get/1, put/2]}).

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

%% Launcher and creator.
-export([start/1, create/1, create/2]).

%%-- Message helpers.
%% Generic.
-export([call/2, call/3,
         cast/2,
         reply/2,
         relay/3, relay/4
        ]).

%% Operations.
-export([stop/1, stop/2,
         subscribe/1, subscribe/2,
         unsubscribe/2,
         notify/2
        ]).

%% Access.
-export([get/1, get/2,
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
%% Attributes.
-export([chain/2,
         chain_action/3, chain_action/4,
         chain_actions/3,
         chain_callback/4,
         merge/2
        ]).
%% Internal process.
-export([handle/2,
         state_call/3,
         asyn_call/4,
         asyn_call/5,
         refer/4,
         invoke/3,
         attach/2, attach/3,
         detach/2,
         bind/2,
         unbind/2,
         access/3
        ]).


%%- Types.
%%------------------------------------------------------------------------------
-export_type([state/0,
              reply/0,
              result/0,
              message/0,
              from/0,
              target/0,
              process/0,
              template/0
             ]).

%%-- Definitions for gen_server.
-type server_name() :: {local, atom()} |
                       {global, atom()} |
                       {via, atom(), term()}.
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
                   'pending_calls' => #{reference() => callback()},
                   'bonds' => 'all' | sets:sets(),
                   'start_options' => start_opt(),
                   'register_name' => server_name(),
                   'run_mode' => 'solo' | 'aggregation',
                   tag() => dynamic_attribute() | any()
                  }.

%%-- Attributes types.
-type dynamic_attribute() :: map() | function() | pid().
-type entry_fun() :: fun((state()) -> state()).
-type exit_fun() :: fun((state()) -> state()).
-type do_fun() :: fun((message() | any(), state()) -> result()).
-type timestamp() :: integer().  % by unit of microseconds.
-type status() :: 'running' | tag().

%%-- Refined types.
-type tag() :: any().
-type pass() :: 'ok' | 'noreply' | 'unhandled' | any().
-type fail() :: {'error', Error :: any()}.
-type reply() :: pass() | fail().
-type refer() :: {'refer', target(), state()} |
                 {'refer', target(), command(), state()}. 
-type stop() :: {'stop', Reason :: any(), state()} |
                {'stop', Reason :: any(), reply(), state()}.
-type result() :: {reply(), state()} | refer() | stop().
-type cb_func() :: fun((reply(), Args :: any(), state()) -> state()).
-type callback() :: {cb_func(), Args :: any()}.
-type position() :: 'head' | 'tail' | integer().

%%-- Messages.
-type message() :: {'$$', command()} |
                   {'$$', target(), command()} |
                   {'$$', from(), target(), command()} |
                   any().
-type path() :: list().
-type from() :: {pid(), reference()} | 'call' | 'cast'.
-type command() :: method() |
                   {method(), any()} |
                   {method(), any(), any()} |
                   any().
-type method() :: 'get' |
                  'put' |
                  'patch' |
                  'delete' |
                  'new' |
                  'stop' |
                  tag().
-type process() :: pid() | atom().
-type target() :: process() | path() | {process(), path()} | tag().

%%-- actors
-type actor_type() :: 'stem' | 'actor' | 'fsm' | 'thing'.
-type template() :: actor_type() | module() |
                    [actor_type() | map()] | function().


%%- MACROS
%%------------------------------------------------------------------------------
-define(DFL_TIMEOUT, 4000).
-define(DFL_MAX_STEPS, infinity).  % self-destructure as brute self-heal.


%%- Starts the server
%%------------------------------------------------------------------------------
-spec start(state()) -> start_ret().
start(State) ->
    Opts = maps:get(start_options, State, []),
    Solo = ({ok, solo} =:= maps:find(run_mode, State)),
    case maps:find(register_name, State) of
        {ok, Name} when Solo ->
            gen_server:start(Name, ?MODULE, State, Opts);
        {ok, Name} ->
            S = add_bond(self(), State),
            gen_server:start_link(Name, ?MODULE, S, Opts);
        error when Solo ->
            gen_server:start(?MODULE, State, Opts);
        error ->
            S = add_bond(self(), State),
            gen_server:start_link(?MODULE, S, Opts)
    end.


%%!future: merge create function into entry to unify state object factory.
-spec create(template()) -> state().
create(Template) ->
    create(Template, #{}).

-spec create(template(), map()) -> state().
%% stem: state().
create(stem, Data) ->
    Data;
%% fsm: stem, start, $state, $fsm, states, step, max_steps, sign, payload.
create(fsm, Data) ->
    enable(Data, [subscribe, fsm]);
%% actor: stem, subscribers, _subscribers, links, monitors, _monitors,
%% report_items, surname, parent.
create(actor, Data) ->
    enable(Data, [link, subscribe, monitor]);
%% thing: stem, fsm, actor.
create(thing, Data) ->
    enable(Data, [link, subscribe, monitor, fsm]);
create(Module, Data) when is_atom(Module) ->
    from_module(Module, Data);
create(Template, Data) when is_list(Template) ->
    enable(Data, Template);
create(Forge, Data) when is_function(Forge) ->
    Forge(Data).

enable(Data, []) ->
    Data;
enable(Data, [link | Rest]) ->
    D = chain_action(Data, do, fun links_do/2),
    enable(D, Rest);
enable(Data, [fsm | Rest]) ->
    D = chain_action(Data, do, fun fsm_do/2),
    enable(D, Rest);
enable(Data, [subscribe | Rest]) ->
    Sub = maps:get(subscribers, Data, fun subscribers/3),
    D1 = Data#{subscribers => Sub},
    D2 = chain_action(D1, do, fun subscribers_do/2),
    D3 = chain_action(D2, exit, fun subscribers_exit/1),
    enable(D3, Rest);
enable(Data, [monitor | Rest]) ->
    Sub = maps:get(monitors, Data, fun monitors/3),
    D1 = Data#{monitors => Sub},
    D2 = chain_action(D1, do, fun monitors_do/2),
    D3 = chain_action(D2, exit, fun monitors_exit/1),
    enable(D3, Rest);
enable(Data, [Template | Rest]) ->
    D = merge(Template, Data),
    enable(D, Rest).


-spec from_module(module(), map()) -> state().
from_module(Module, Data) ->
    case erlang:function_exported(Module, create, 1) of
        true ->
            Module:create(Data);
        _ ->
            Attributes = Module:module_info(attributes),
            Functions = Module:module_info(exports),
            D0 = maps:from_list(Attributes),
            D1 = lists:foldl(fun({F, A}, D) ->
                                    D#{F => fun Module:F/A}
                             end, D0, Functions),
            merge(D1, Data)
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

on_entry(#{entry := Entry} = State) when is_function(Entry) ->
    Entry(State);
on_entry(#{entry := Entry} = State) ->
    lists:foldl(fun(F, S) -> F(S) end,
                State,
                Entry);
on_entry(State) ->
    State.


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
        {refer, NextHop, S} ->
            catch NextHop ! Info,
            {noreply, S};
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

on_exit(#{exit := Exit} = State) when is_function(Exit) ->
    Exit(State);
on_exit(#{exit := Exit} = State) ->
    lists:foldl(fun(F, S) ->
                        try
                            F(S)
                        catch
                            _:_ -> S
                        end
                end, State, Exit);
on_exit(State) ->
    State.


%% Convert process state when code is changed
%%
%% -callback code_change(OldVsn :: (term() | {down, term()}), State :: term(),
%%                       Extra :: term()) ->
%%     {ok, NewState :: term()} | {error, Reason :: term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%- Message processing.
%%------------------------------------------------------------------------------
-spec call(target(), command()) -> reply().
call([Process | Path], Command) ->
    call(Process, Path, Command, infinity);
call({Process, Path}, Command) ->
    call(Process, Path, Command, infinity);
call(Process, Command) ->
    call(Process, [], Command, infinity).

-spec call(target(), command(), timeout()) -> reply().
call([Process | Path], Command, Timeout) ->
    call(Process, Path, Command, Timeout);
call({Process, Path}, Command, Timeout) ->
    call(Process, Path, Command, Timeout);
call(Process, Command, Timeout) ->
    call(Process, [], Command, Timeout).

-spec call(process(), path(), command(), timeout()) -> reply().
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


-spec cast(target(), command()) -> 'ok'.
cast([Process | Path], Command) ->
    cast(Process, Path, Command);
cast({Process, Path}, Command) ->
    cast(Process, Path, Command);
cast(Process, Command) ->
    cast(Process, [], Command).

-spec cast(process(), path(), Message :: any()) -> 'ok'.
cast(Process, Path, Message) ->
    catch Process ! {'$$', cast, Path, Message},
    ok.


-spec reply({tag(), reference()}, Reply :: any()) -> 'ok'.
reply({To, Tag}, Reply) ->
    catch To ! {Tag, Reply},
    ok;
reply(_, _) ->
    ok.


-spec relay(from(), target(), command()) -> 'ok'.
relay(From, [To | Path], Command) ->
    relay(From, To, Path, Command);
relay(From, {To, Path}, Command) ->
    relay(From, To, Path, Command);
relay(From, To, Command) ->
    relay(From, To, [], Command).

-spec relay(from(), process(), path(), command()) -> 'ok'.
relay(From, To, Path, Command) ->
    catch To ! {'$$', From, Path, Command},
    ok.


%%-- Data access.
%%------------------------------------------------------------------------------
-spec get(target()) -> reply().
get(Path) ->
    call(Path, get).

-spec get(target(), Options :: any()) -> reply().
get(Path, Options) ->
    call(Path, {get, Options}).


-spec put(target(), Value :: any()) -> reply().
put(Path, Value) ->
    call(Path, {put, Value}).

-spec put(target(), Value :: any(), Options :: any()) -> reply().
put(Path, Value, Options) ->
    call(Path, {put, Value, Options}).


-spec patch(target(), Value :: any()) -> reply().
patch(Path, Value) ->
    call(Path, {patch, Value}).

-spec patch(target(), Value :: any(), Options :: any()) -> reply().
patch(Path, Value, Options) ->
    call(Path, {patch, Value, Options}).


-spec new(target(), Value :: any()) -> reply().
new(Path, Value) ->
    call(Path, {new, Value}).

-spec new(target(), Value :: any(), Options :: any()) -> reply().
new(Path, Value, Options) ->
    call(Path, {new, Value, Options}).


-spec delete(target()) -> reply().
delete(Path) ->
    call(Path, delete).

-spec delete(target(), Options :: any()) -> reply().
delete(Path, Options) ->
    call(Path, {delete, Options}).


%%-- Operations.
%%------------------------------------------------------------------------------
-spec subscribe(target()) -> reply().
subscribe(Path) ->
    Target = chain(Path, subscribers),
    call(Target, {new, self()}).

-spec subscribe(target(), pid()) -> reply().
subscribe(Path, Pid) ->
    Target = chain(Path, subscribers),
    call(Target, {new, Pid}).


-spec unsubscribe(target(), reference()) -> reply().
unsubscribe(Path, Ref) ->
    Target = chain(Path, [subscribers, Ref]),
    call(Target, delete).


-spec notify(target(), Info :: any()) -> reply().
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


-spec chain_action(state(), tag(), any()) -> state().
chain_action(State, Name, Action) ->
    chain_action(State, Name, Action, tail).

-spec chain_action(state(), tag(), any(), position()) -> state().
chain_action(State, Name, Action, Position) ->
    case maps:find(Name, State) of
        error ->
            State#{Name => Action};
        {ok, L} when Position =:= head ->
            State#{Name := chain(Action, L)};
        {ok, L} when Position =:= tail ->
            State#{Name := chain(L, Action)}
    end.


-spec chain_actions(state(), state(), [tag()]) -> state().
chain_actions(State1, State2, Actions) ->
    Func = fun(Key, State) ->
                   case maps:find(Key, State2) of
                       {ok, Value} ->
                           chain_action(State, Key, Value, tail);
                       error ->
                           State
                   end
           end,
    lists:foldl(Func, State1, Actions).


-spec chain(Head :: target(), Tail :: any()) -> list().
chain({Process, Path}, Tail) ->
    NewPath = chain(Path, Tail),
    {Process, NewPath};
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

on_event([Do | Rest], Info, State) ->
    case Do(Info, State) of
        {unhandled, S} ->
            on_event(Rest, Info, S);
        Handled ->
            Handled
    end;
on_event([], _, State) ->
    {unhandled, State}.


%%-- sop messages.
-spec handle(command(), state()) -> result().
handle({'$$', From, To, Command}, State) ->
    response(Command, From, request(Command, To, From, State));
handle({'$$', From, Command}, State) ->
    response(Command, From, request(Command, [], From, State));
handle({'$$', Command}, State) ->
    response(Command, cast, request(Command, [], cast, State));
handle({Ref, Result}, State) ->
    handle_result(Ref, Result, State);
handle({'DOWN', M, _, _, Reason}, State) ->
    handle_result(M, {error, Reason}, State);
handle({'EXIT', _, _} = Break, State) ->
    handle_break(Break, State);
%% Drop unknown messages. Nothing replied.
handle(_, State) ->
    {noreply, State}.

handle_result(Ref, Result, #{pending_calls := Q} = State) ->
    %% Timeout control of asynchnous call may be implemented by send_after
    %% function.
    case maps:take(Ref, Q) of
        {{Func, Arg}, Q1} ->
            case Func(Result, Arg, State) of
                {done, State1} ->
                    catch demonitor(Ref),
                    {noreply, State1#{pending_calls := Q1}};
                {pending, State1} ->
                    {noreply, State1};
                Stop -> % should be stop result.
                    Stop
            end;
        {Callbacks, Q1} when is_list(Callbacks) ->
            case lists:foldr(fun do_callbacks/2,
                             {Result, State, []}, Callbacks) of
                {_, State1, []} ->
                    catch demonitor(Ref),
                    {noreply, State1#{pending_calls := Q1}};
                {_, State1, Rest} ->
                    Q2 = Q#{Ref := Rest},
                    {noreply, State1#{pending_calls := Q2}}
            end;
        _ ->  % do nothing and keep State untouched.
            {noreply, State}
    end;
handle_result(_, _, State) ->
    {noreply, State}.

do_callbacks({F, A}, {R, S, L}) ->
    case F(R, A, S) of
        {done, S1} ->
            {R, S1, L};
        {pending, S1} ->
            {R, S1, [{F, A} | L]};
        {stop, Reason, _} ->
            exit(Reason)
    end.

handle_break(Break, #{bonds := all} = State) ->
    {stop, {shutdown, Break}, State};
handle_break({_, Pid, _} = Break, #{bonds := Cl} = State) ->
    case sets:is_element(Pid, Cl) of
        true ->
            {stop, {shutdown, Break}, State};
        false ->
            {noreply, State}
    end;
handle_break(_, State) ->
    {noreply, State}.

%%-- Reply and normalize result of request.
response(_, _, {noreply, NewState}) ->
    {noreply, NewState};
response(_, Caller, {Reply, NewState}) ->
    reply(Caller, Reply),
    {noreply, NewState};
response(Command, Caller, {refer, Target, NewState}) ->
    refer(Caller, Target, Command, NewState);
response(_, Caller, {refer, Target, Command, NewState}) ->
    refer(Caller, Target, Command, NewState);
response(_, Caller, {stop, Reason, NewState}) ->
    reply(Caller, stopping),
    {stop, Reason, NewState};
response(_, Caller, {stop, Reason, Reply, NewState}) ->
    reply(Caller, Reply),
    {stop, Reason, NewState}.

%% Invoke on root of actor.
request(Command, [], _, State) ->
    do_(Command, State);
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
            {refer, {Pid, Sprig}, State}
    end.

do_(stop, State) ->
    {stop, normal, State};
do_({stop, Reason},  State) ->
    {stop, Reason, State};
do_(Command, State) ->
    %% Support: get, {get, Selection}, {patch, Value}, {new, Value}
    case access(Command, [], State) of
        {result, Res} ->
            {Res, State};
        {update, Reply, NewS} when (not is_tuple(Command));
                                   element(1, Command) =/= put ->
            {Reply, NewS};
        _ ->
            {{error, badarg}, State}
    end.


%% get, delete and put with [Key] is handled by the parent attribute, not by the
%% Key attribute. patch and new methods with [Key] are odd, they are handled by
%% Key attribute when it is active (function or process) while they are handled
%% by parent when Key attribute is map type.
-spec access(command(), target(), Package :: any()) -> 
                    {'result', any()} |
                    {'update', tag(), any()} |
                    {'delete', 'ok'} |
                    {'action', function()} |
                    {'actor', pid()}.
%%--- Raw value of the attribute.
access({get, raw}, [], Data) ->
    {result, Data};
access({put, Value, raw}, [], _) ->
    {update, ok, Value};
access({delete, raw}, [], _) ->
    {delete, ok};
%%--- Active attributes.
access(_, Sprig, Data) when is_function(Data) ->
    {action, Data, Sprig};
access(_, Sprig, Data) when is_pid(Data) ->
    {actor, Data, Sprig};
%%--- The value of attribute or map type attributes.
access(get, [], Data) ->
    {result, Data};
access({put, Value}, [], _) ->
    {update, ok, Value};
access(delete, [], _) ->
    {delete, ok};
access({get, Selection}, [], Data)
  when is_list(Selection) ->
    Value = maps:with(Selection, Data),
    {result, Value};
access({patch, Value}, [], Data)
  when is_map(Value) ->
    NewData = maps:merge(Data, Value),
    {update, ok, NewData};
access({new, Value, #{key := Key}}, [], Data) ->
    {update, Key, Data#{Key => Value}};
access({new, Value}, [], Data) ->
    {Key, NewData} = new_attribute(Value, Data),
    {update, Key, NewData};
access(Command, [Key | Rest], Data) ->
    case maps:find(Key, Data) of
        {ok, Value} ->
            case access(Command, Rest, Value) of
                {update, Reply, NewValue} ->
                    {update, Reply, Data#{Key => NewValue}};
                {delete, ok} ->
                    {update, ok, maps:remove(Key, Data)};
                Result ->
                    Result
            end;
        error ->
            {result, {error, undefined}}
    end;
access(_, [], _) ->
    {result, {error, badarg}};
%% Wrap Key into path list.
access(Command, Key, State) ->
    access(Command, [Key], State).


-spec perform(function(), command(), target(), from(), state()) -> result().
perform(Func, Command, Sprig, From, State) when is_function(Func, 4) ->
    Func(Command, Sprig, From, State);
perform(Func, Command, Sprig, _, State) when is_function(Func, 3) ->
    Func(Command, Sprig, State);
perform(Func, Command, _, _, State) when is_function(Func, 2) ->
    Func(Command, State);
perform(Func, _, _, _, State) ->
    Func(State).


-spec refer(from(), To :: target(), command(), state()) -> result().
refer(Caller, Path, Command, State) when is_list(Path) ->
    handle_info({'$$', Caller, Path, Command}, State);
refer(Caller, {Process, Path}, Command, State) ->
    catch Process ! {'$$', Caller, Path, Command},
    {noreply, State};
refer(Caller, Process, Command, State) ->
    catch Process ! {'$$', Caller, [], Command},
    {noreply, State}.


%%- Internal state operation.
-spec invoke(command(), target(), state()) -> result().
invoke(Command, Path, State) ->
    case access(Command, Path, State) of
        {result, Res} ->
            {Res, State};
        {update, Reply, NewState} ->
            {Reply, NewState};
        {action, Func, Route} ->
            %% Caller is call means neither aynchronous return nor forwarding.
            case perform(Func, Command, Route, call, State) of
                {refer, Next, S} when is_list(Next) ->
                    invoke(Command, Next, S);
                {refer, Next, S} ->
                    state_call(Next, Command, S);
                {refer, Next, NewCmd, S} when is_list(Next) ->
                    invoke(NewCmd, Next, S);
                {refer, Next, NewCmd, S} ->
                    state_call(Next, NewCmd, S);
                Result ->
                    Result
            end;
        {actor, Pid, Sprig} ->
            state_call({Pid, Sprig}, Command, State);
        {delete, ok} ->
            {{error, badarg}, State}
    end.


-spec state_call(target(), command(), state()) -> {Result :: any(), state()}.
state_call(Target, Command, State) ->
    Timeout = maps:get(timeout, State, ?DFL_TIMEOUT),
    Result = call(Target, Command, Timeout),
    {Result, State}.


-spec asyn_call(target(), command(), callback(), state()) ->
                        {Result :: any(), state()}.
asyn_call([Process | Path], Command, Callback, State) ->
    asyn_call(Process, Path, Command, Callback, State);
asyn_call({Process, Path}, Command, Callback, State) ->
    asyn_call(Process, Path, Command, Callback, State);
asyn_call(Process, Command, Callback, State) ->
    asyn_call(Process, [], Command, Callback, State).


-spec asyn_call(process(), path(), command(), callback(), state()) -> reply().
asyn_call(Process, Path, Command, Callback, State) ->
    Tag = monitor(process, Process),
    Process ! {'$$', {self(), Tag}, Path, Command},
    S = enqueue_callback(Tag, Callback, State),
    {Tag, S}.


-spec enqueue_callback(tag(), callback(), state()) -> state().
enqueue_callback(Tag, Callback, State) ->
    Q = maps:get(pending_calls, State, #{}),
    Q1 = Q#{Tag => Callback},
    State#{pending_calls => Q1}.

-spec chain_callback(tag(), callback(), position(), state()) -> state().
chain_callback(Tag, Callback, Position, State) ->
    Q = maps:get(pending_calls, State, #{}),
    Q1 = chain_action(Q, Tag, [Callback], Position),
    State#{pending_calls => Q1}.

-spec attach(tag(), state()) -> result().
attach(Key, State) ->
    Path = chain(links, Key),
    case invoke(get, Path, State) of
        {{error, _}, _} = Error ->
            Error;
        {Value, S1} ->
            attach(Key, Value, S1);
        Stop ->
            Stop
    end.


-spec attach(tag(), Value :: any(), state()) -> result().
attach(Key, Pid, State) when is_pid(Pid) ->
    case invoke({new, {Key, Pid}}, [monitors], State#{Key => Pid}) of
        {_, S} ->
            {ok, S};
        Stop ->
            Stop
    end;
attach(Key, Func, State) when is_function(Func) ->
    {ok, State#{Key => Func}};
attach(Key, {state, S}, State) ->
    S1 = S#{surname => Key, parent => self()},
    case start(S1) of
        {ok, Pid} ->
            case invoke({new, {Key, Pid}},
                        [monitors], State#{Key => Pid}) of
                {_, State1} ->
                    {ok, State1};
                Stop ->
                    Stop
            end;
        Error ->
            {Error, State}
    end;
%% To accept pid() or {state, any()} Value as raw data.
attach(Key, {data, Value}, State) ->
    {ok, State#{Key => Value}};
attach(_, _, State) ->
    {{error, badarg}, State}.


-spec detach(tag(), state()) -> result().
detach(Key, State) ->
    case invoke(delete, [monitors, Key], State) of
        {_, S} ->
            case maps:take(Key, S) of
                error ->
                    {ok, S};
                Result ->
                    Result
            end;
        Stop ->
            Stop
    end.


-spec bind(pid(), state()) -> state().
bind(Pid, State) ->
    true = link(Pid),
    add_bond(Pid, State).

-spec unbind(pid(), state()) -> state().
unbind(Pid, State) ->
    unlink(Pid),
    remove_bond(Pid, State).

add_bond(_, #{bonds := all} = State) ->
    State;
add_bond(Pid, #{bonds := B} = State) ->
    B1 = sets:add_element(Pid, B),
    State#{bonds := B1};
add_bond(Pid, State) ->
    B = sets:new(),
    B1 = sets:add_element(Pid, B),
    State#{bonds => B1}.

remove_bond(_, #{bonds := all} = State) ->
    State;
remove_bond(Pid, #{bonds := B} = State) ->
    B1 = sets:del_element(Pid, B),
    State#{bonds := B1};
remove_bond(_, State) ->
    State.


%%- Actor behaviors.
%%------------------------------------------------------------------------------

%%-- Behaviors of subscribe & notification.
%%------------------------------------------------------------------------------
%% Introduced:
%%  * 'subscribers': active attribute for subscription actions.
%%  * '_subscribers': subscribers data cache.
%%  * 'report_items': definition of output items when actor exit.
subscribers({new, Pid}, [], State) ->
    Subs = maps:get('_subscribers', State, #{}),
    Mref = monitor(process, Pid),
    Subs1 = Subs#{Mref => Pid},
    {Mref, State#{'_subscribers' => Subs1}};
subscribers({notify, Info}, [], #{'_subscribers' := Subs} = State) ->
    maps:fold(fun(M, P, _) -> catch P ! {M, Info} end, 0, Subs),
    {ok, State};
subscribers({notify, Info, remove}, [], #{'_subscribers' := Subs} = State) ->
    maps:fold(fun(Mref, Pid, _) ->
                      catch Pid ! {Mref, Info},
                      demonitor(Mref)
              end, 0, Subs),
    {ok, maps:remove('_subscribers', State)};
subscribers(delete, [Mref], #{'_subscribers' := Subs} = State) ->
    demonitor(Mref),
    Subs1 = maps:remove(Mref, Subs),
    {ok, State#{'_subscribers' := Subs1}};
subscribers(delete, Mref, State) ->
    subscribers(delete, [Mref], State);
subscribers(_, _, State) ->
    {{error, badarg}, State}.

subscribers_do({'DOWN', M, _, _, _}, State) ->
    case maps:find('_subscribers', State) of
        {ok, Subs} ->
            Subs1 = maps:remove(M, Subs),
            {noreply, State#{'_subscribers' := Subs1}};
        error ->
            {unhandled, State}
    end;
subscribers_do(_, State) ->
    {unhandled, State}.

subscribers_exit(State) ->
    Detail = maps:get('report_items', State, []),
    Report = make_report(Detail, State),
    Info = {exit, Report},
    {_, S} = invoke({notify, Info, remove}, [subscribers], State),
    S.

%% Selective report.
make_report(all, State) ->
    State;
%% Selections is a list of attributes to yield.
make_report(Selections, State) when is_list(Selections) ->
    maps:with(Selections, State).


%%-- Behaviors of monitor.
%%------------------------------------------------------------------------------
monitors(get, [Id], #{'_monitors' := M} = State) ->
    case maps:find(Id, M) of
        error ->
            {{error, undefined}, State};
        {ok, Value} ->
            {Value, State}
    end;
monitors(delete, [Id], #{'_monitors' := M} = State) ->
    case maps:find(Id, M) of
        {ok, {Mref, Key, _}} ->
            demonitor(Mref),
            M1 = maps:remove(Mref, M),
            M2 = maps:remove(Key, M1),
            {ok, State#{'_monitors' := M2}};
        error ->
            {{error, undefined}, State}
    end;
monitors({delete, all}, [], State) ->
    %% Cleanup but do not demonitor. Monitors can be released when process
    %% exiting.
    {ok, maps:remove('_monitors', State)};
monitors({demonitor, all}, [], #{'_monitors' := M} = State) ->
    %% Demonitor and remove all monitors. 'DOWN' message will not be fired when
    %% current actor process stopped.
    maps:fold(fun(Mref, {Mref, _, _}, _) ->
                      demonitor(Mref, [flush]);
                 (_, _, _) ->
                      false
              end, false, M),
    {ok, maps:remove('_monitors', State)};
monitors({new, V}, [], State) ->
    M = maps:get('_monitors', State, #{}),
    {Ref, M1} = new_monitor(V, M),
    {Ref, State#{'_monitors' => M1}};
monitors({'DOWN', Mref, _, _Pid, Reason}, [], #{'_monitors' := M} = State) ->
    case maps:take(Mref, M) of
        {{Mref, Key, true}, M1} ->
            %% Remove monitor but keep Key in State.
            M2 = maps:remove(Key, M1),
            {_, S1} = invoke({delete, raw}, Key, State#{'_monitors' := M2}),
            {stop, {shutdown, Reason}, S1};
        {{Mref, Key, false}, M1} ->
            M2 = maps:remove(Key, M1),
            {_, S1} = invoke({delete, raw}, Key, State#{'_monitors' := M2}),
            {noreply, S1};
        _ ->
            {unhandled, State}
    end;
monitors({'DOWN', _, _, _, _}, [], State) ->
    {unhandled, State};
monitors(_, _, State) ->
    {{error, badarg}, State}.

monitors_do({'$$', _, Key, delete}, State) ->
    case invoke(delete, [monitors, Key], State) of
        {_, S} ->
            {unhandled, S};
        Stop ->
            Stop
    end;
monitors_do({'DOWN', _, _, _, _} = Down, State) ->
    invoke(Down, [monitors], State);
monitors_do(_, State) ->
    {unhandled, State}.

monitors_exit(State) ->
    {_, S} = invoke({delete, all}, [monitors], State),
    S.

new_monitor({Key, Pid, Bond}, M) when is_pid(Pid) ->
    Mref = monitor(process, Pid),
    V = {Mref, Key, Bond},
    {Mref, M#{Mref => V, Key => V}};
new_monitor({Key, Mref, Bond}, M) ->
    V = {Mref, Key, Bond},
    {Mref, M#{Mref =>V, Key => V}};
new_monitor({K, V}, M) ->
    new_monitor({K, V, false}, M).


%%-- Behaviors of link.
%%------------------------------------------------------------------------------
links_do({'$$', _, [links | _], _}, State) ->
    {unhandled, State};
links_do({'$$', _, _, delete}, State) ->
    {unhandled, State};
links_do({'$$', From, [Key | _] = Path, Command}, #{links := L} = State) ->
    %%!todo: optimize repeat fetching of Key.
    case maps:is_key(Key, State) of
        true ->
            {unhandled, State};
        false when is_map(L) ->
            case maps:find(Key, L) of
                error ->
                    reply(From, {error, undefined}),
                    {noreply, State};
                {ok, Value} ->
                    case attach(Key, Value, State) of
                        {ok, S} ->
                            {unhandled, S};
                        {Error, S} ->
                            reply(From, Error),
                            {noreply, S};
                        Stop ->
                            Stop
                    end
            end;
        false ->
            refer(From, [links | Path], Command, State)
    end;
links_do(_, State) ->
    {unhandled, State}.


%%-- Behaviors of Finite State Machine.
%%------------------------------------------------------------------------------
-spec swap(state()) -> state().
swap(#{'$state' := S} = Fsm) ->
    S#{'$fsm' => maps:remove('$state', Fsm)};
swap(#{'$fsm' := F} = State) ->
    F#{'$state' => maps:remove('$fsm', State)}.


%% If $state is present before FSM start, it is an introducer for flexible
%% initialization.
fsm_do({'$$', _, [links | _], _}, Fsm) ->
    {unhandled, Fsm};
fsm_do({'$$', _, [subscribers | _], _}, Fsm) ->
    {unhandled, Fsm};
fsm_do({'$$', _, [monitors | _], _}, Fsm) ->
    {unhandled, Fsm};
fsm_do(Info, #{'$state' := _} = Fsm) ->
    do_state(Info, swap(Fsm));
fsm_do('$$enter', Fsm) ->
    start_fsm(Fsm);
fsm_do(_, Fsm) ->
    {unhandled, Fsm}.

start_fsm(#{start := Start} = Fsm) when is_function(Start) ->
    Start(Fsm);
start_fsm(#{start := Start} = Fsm) ->
    transition(Start, Fsm);
start_fsm(Fsm) ->
    {unhandled, Fsm}.

%%!todo: archive historic states as traces.
%%        {_, F1} = invoke({new, Fsm}, [traces], Fsm),            
transition(Sign, Fsm) ->
    Step = maps:get(step, Fsm, 0),
    F1 = Fsm#{step => Step + 1},
    %% Asynchronously notify.
    cast([self(), subscribers], {notify, {transition, Step, Sign}}),
    %% states should handle exceptions. For examples: vertex of sign is not
    %% found or exceed max steps limited.
    case invoke(get, [states, Sign], F1) of
        {{error, _} = Error, F2} ->
            {stop, {shutdown, Error}, F2};
        {State, F2} ->
            enter_state(F2#{'$state' => State});
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
    try handle_info(Info, State) of
        {noreply, S} ->
            {noreply, swap(S)};
        {stop, normal, S} ->
            S1 = on_exit(S),
            Sign = maps:get(sign, S1, stop),
            transition(Sign, swap(S1));
        {stop, Shutdown, S} ->
            {stop, Shutdown, swap(S)}
    catch
        error : function_clause when element(1, Info) =:= '$$' ->
            reply(element(2, Info), {error, unknown}),
            {noreply, swap(State)};
        C : E ->
            Fsm = swap(State),
            transition(exception, Fsm#{payload => {C, E}})
    end.
