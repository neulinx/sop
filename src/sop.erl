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
-export([reply/2]).
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
-type code() :: 'ok' | 'error' | 'noreply' | 'stop' | 'unhandled' | tag().
-type result() :: {any(), state()} |
                  {code(), any(), state()} |
                  {stop, Reason :: any(), Reply :: any(), state()}.

%%-- Messages.
-type signal() :: {'sos', command()} |
                  {'sos', to(), command()} |
                  {'sos', from(), to(), command()}.
-type to() :: list() | tag().
-type from() :: {pid(), reference()} | 'call' | 'cast'.
-type command() :: method() | {method(), any()} | {'new', any(), any()} | any().
-type method() :: 'get' | 'put' | 'patch' | 'delete' | 'new' | tag().

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
                    handle(Info, S);
                Res0 ->
                    Res0
            end;
        error ->
            handle(Info, State)
    end.

%%-- sop messages.
handle({sos, From, To, Command}, State) ->
    request(To, Command, From, State);
handle({sos, From, Command}, State) ->
    request([], Command, From, State);
handle({sos, Command}, State) ->
    request([], Command, cast, State);
%%-- drop unknown messages.
handle(_, State) ->
    {noreply, State}.

%% Invoke at root of actor.
request(Command, [], From, State) ->
    case access(Command, [], State) of
        {result, Res} ->
            reply(From, Res),
            {noreply, State};
        {update, Reply, NewS} when (not is_tuple(Command));
                                   element(1, Command) =/= put ->
            reply(From, Reply),
            {noreply, NewS};
        _ ->
            reply(From, {error, badarg}),
            {noreply, State}
    end;
%% Branches and sprig.
request(Command, To, From, State) ->
    case access(Command, To, State) of
        {result, Res} ->
            reply(From, Res),
            {noreply, State};
        {update, Reply, NewState} ->
            reply(From, Reply),
            {noreply, NewState};
        {action, Func, Route} ->
            case perform(Func, Command, Route, From, State) of
                {noreply, _} = Result ->
                    Result;
                {noreply, _, _} = Result ->
                    Result;
                {stop, _, _} = Result ->
                    Result;
                {stop, _, _, _} = Result ->
                    Result;
                {Reply, NewState} ->
                    reply(From, Reply),
                    {noreply, NewState};
                {Code, Res, NewState} ->
                    reply(From, {Code, Res}),
                    {noreply, NewState}
            end;
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

-spec reply({tag(), reference()}, Reply :: any()) -> 'ok'.
reply({To, Tag}, Reply) ->
    catch To ! {Tag, Reply},
    ok;
reply(_, _) ->
    ok.

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


%%- Miscellaneous.
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
