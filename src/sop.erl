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
%%-- gen_server callbacks
-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%%-- Launcher and creator.
-export([start_link/1, start_link/2, start_link/3]).
-export([start/1, start/2, start/3]).

%%-- Helpers
-export([reply/2,
         call/2, call/3, call/4,
         cast/2, cast/3,
         stop/1, stop/2]).
-export([get/1, get/2,
         put/2, put/3,
         patch/2, patch/3,
         new/2, new/3,
         delete/1, delete/2]).
-export([timestamp/0, make_tag/0, make_tag/1, new_attribute/2]).

%%- MACROS
%%------------------------------------------------------------------------------
-define(DFL_TIMEOUT, 4000).

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
-type state() :: #{'entry' => entry_fun(),
                   'exit' => exit_fun(),
                   'do' => do_fun(),
                   'pid' => pid(),
                   'entry_time' => timestamp(),
                   'exit_time' => timestamp(),
                   'status' => status(),
                   'timeout' => timeout(),
                   tag() => dynamic_attribute() | any()
                  }.

%%-- Attributes types.
-type dynamic_attribute() :: map() | function() | pid().
-type entry_fun() :: fun((state()) -> result()).
-type exit_fun() :: fun((state()) -> result()).
-type do_fun() :: fun((signal() | any(), state()) -> result()).
-type timestamp() :: integer().  % by unit of microseconds.
-type status() :: 'running' | tag().

%%-- Refined types.
-type tag() :: atom() | string() | binary() | integer() | tuple().
-type code() :: 'ok' | 'error' | 'noreply' | 'stop' |
                'stopping' | 'unhandled' | tag().
-type result() :: {any(), state()} |
                  {code(), any(), state()} |
                  {stop, Reason :: any(), Reply :: any(), state()}.
-type reply() :: code() | {code(), Result :: any()}.

%%-- Messages.
-type signal() :: {'sos', command()} |
                  {'sos', path(), command()} |
                  {'sos', from(), path(), command()}.
-type path() :: list() | tag().
-type from() :: {pid(), reference()} | 'call' | 'cast'.
-type command() :: method() | {method(), any()} | {'new', any(), any()} | any().
-type method() :: 'get' | 'put' | 'patch' | 'delete' | 'new' | 'stop' | tag().
-type process() :: pid() | atom().
-type target() :: process() | path().

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

%% gen_server callbacks
%%------------------------------------------------------------------------------
%% Initializes the server
%% -callback init(Args :: term()) ->
%%     {ok, State :: term()} | {ok, State :: term(), timeout() | hibernate} |
%%     {stop, Reason :: term()} | ignore.
init(State) ->
    process_flag(trap_exit, true),
    S0 = #{entry_time => timestamp(),
           pid => self(),
           status => running,
           timeout => ?DFL_TIMEOUT},
    S1 = maps:merge(S0, State),
    on_entry(S1).

on_entry(#{entry := Entry} = State) ->
    Entry(State);
on_entry(State) ->
    {ok, State}.

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
    handle_info({sos, From, To, {Method, Args}}, State);
handle_call({To, Method}, From, State) ->
    handle_info({sos, From, To, Method}, State);
handle_call(Method, From, State) ->
    handle_info({sos, From, [], Method}, State).


%% Handling async cast messages.
%% 
%% -callback handle_cast(Request :: term(), State :: term()) ->
%%     {noreply, NewState :: term()} |
%%     {noreply, NewState :: term(), timeout() | hibernate} |
%%     {stop, Reason :: term(), NewState :: term()}.
handle_cast({To, Method, Args}, State) ->
    handle_info({sos, cast, To, {Method, Args}}, State);
handle_cast({To, Method}, State) ->
    handle_info({sos, cast, To, Method}, State);
handle_cast(Method, State) ->
    handle_info({sos, cast, [], Method}, State).

%% Handling normal messages.
%% 
%% -callback handle_info(Info :: timeout | term(), State :: term()) ->
%%     {noreply, NewState :: term()} |
%%     {noreply, NewState :: term(), timeout() | hibernate} |
%%     {stop, Reason :: term(), NewState :: term()}.
handle_info(Info, State) ->
    case maps:find(do, State) of
        {ok, Do} ->
            case Do(Info, State) of
                {unhandled, S} ->
                    {Result, Caller} = handle(Info, S),
                    response(Result, Caller);
                Res0 ->
                    Res0
            end;
        error ->
            {Result, Caller} = handle(Info, State),
            response(Result, Caller)
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

terminate(Reason, #{exit := Exit} = State) ->
    Exit(Reason, State#{exit_time => timestamp()});
terminate(_Reason, _State) ->
    ok.

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
    Process ! {sos, {self(), Tag}, Path, Command},
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
    catch Process ! {sos, cast, Path, Message},
    ok.

%%-- Data access.
%%------------------------------------------------------------------------------
-spec get(path()) -> result().
get(Path) ->
    call(Path, get).

-spec get(path(), Options :: any()) -> result().
get(Path, Options) ->
    call(Path, {get, Options}).

-spec put(path(), Value :: any()) -> result().
put(Path, Value) ->
    call(Path, {put, Value}).

-spec put(path(), Value :: any(), Options :: any()) -> result().
put(Path, Value, Options) ->
    call(Path, {put, Value, Options}).

-spec patch(path(), Value :: any()) -> result().
patch(Path, Value) ->
    call(Path, {patch, Value}).

-spec patch(path(), Value :: any(), Options :: any()) -> result().
patch(Path, Value, Options) ->
    call(Path, {patch, Value, Options}).

-spec new(path(), Value :: any()) -> result().
new(Path, Value) ->
    call(Path, {new, Value}).

-spec new(path(), tag(), Value :: any()) -> result().
new(Path, Key, Value) ->
    call(Path, {new, Key, Value}).

-spec delete(path()) -> result().
delete(Path) ->
    call(Path, delete).

-spec delete(path(), Options :: any()) -> result().
delete(Path, Options) ->
    call(Path, {delete, Options}).

%%-- Operations.
%%------------------------------------------------------------------------------
-spec stop(target()) -> result().
stop(Path) ->
    call(Path, stop).

-spec stop(target(), Reason :: any()) -> result().
stop(Path, Reason) ->
    call(Path, {stop, Reason}).

%%- Miscellaneous
%%------------------------------------------------------------------------------
timestamp() ->
    erlang:system_time(micro_seconds).

make_tag() ->
    make_tag(8).

make_tag(N) ->
    B = base64:encode(crypto:strong_rand_bytes(N)),
    binary_part(B, 0, N).

new_attribute(Value, Map) ->
    Key = make_tag(),
    case maps:is_key(Key, Map) of
        true ->
            new_attribute(Value, Map);
        false ->
            {Key, Map#{Key => Value}}
    end.

%%- Internal functions.
%%------------------------------------------------------------------------------
%%-- sop messages.
handle({sos, From, To, Command}, State) ->
    {request(Command, To, From, State), From};
handle({sos, From, Command}, State) ->
    {request(Command, [], From, State), From};
handle({sos, Command}, State) ->
    {request(Command, [], cast, State), cast};
%% drop unknown messages.
handle(_, State) ->
    {{noreply, State}, undefined}.

%%-- Reply and normalize result of request.
response({noreply, _} = Noreply, _) ->
    Noreply;
response({Reply, NewState}, Caller) ->
    reply(Caller, Reply),
    {noreply, NewState};
response({noreply, _, _} = Noreply, _) ->
    Noreply;
response({stop, _, _} = Stop, Caller) ->
    reply(Caller, stopping),
    Stop;
response({stop, Reason, Reply, NewState}, Caller) ->
    reply(Caller, Reply),
    {stop, Reason, NewState};
response({Code, Res, NewState}, Caller) ->
    reply(Caller, {Code, Res}),
    {noreply, NewState}.

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
            {error, badarg, State}
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
            catch Pid ! {sos, From, Sprig, Command},
            {noreply, State};
        _ ->
            {error, badarg, State}
    end.

access(get, [], Data) ->
    {result, {ok, Data}};
access({put, Value}, [], _) ->
    {update, ok, Value};
access(delete, [], _) ->
    {delete, ok};
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

