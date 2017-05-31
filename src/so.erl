%%%-------------------------------------------------------------------
%%% @author Gary Hai <gary@XL59.com>
%%% @copyright (C) 2017, Neulinx Inc.
%%% @doc
%%%
%%% @end
%%% Created : 24 May 2017 by Gary Hai <gary@XL59.com>
%%%-------------------------------------------------------------------
-module(so).

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
                   'actions' => dynamic_attribute(),
                   'links' => dynamic_attribute(),
                   tag() => dynamic_attribute() | any()
                  }.

%%-- Attributes types.
-type dynamic_attribute() :: map() | function() | pid().
-type entry_fun() :: fun((state()) -> result()).
-type exit_fun() :: fun((state()) -> result()).
-type do_fun() :: fun((request() | any(), state()) -> result()).
-type timestamp() :: integer().  % by unit of microseconds.
-type status() :: 'running' | 'stopped'.

%%-- Refined types.
-type tag() :: atom() | string() | binary() | integer() | tuple().
-type code() :: 'ok' | 'error' | 'noreply' | 'stop' | 'unhandled' | tag().
-type result() :: {any(), state()} |
                  {code(), any(), state()} |
                  {stop, Reason :: any(), Reply :: any(), state()}.

%%-- Messages.
-type request() :: {'sos', command()} |
                   {'sos', sprig(), command()} |
                   {'sos', via(), sprig(), command()} |
                   {'sos', via(), path(), sprig(), command()}.
-type sprig() :: list().
-type via() :: {pid(), reference()} | 'call' | 'cast'.
-type path() :: list().
-type command() :: method() | {method(), any()} | {method(), any(), any()}.
-type method() :: 'get' | 'put' | 'patch' | 'new' | 'delete' | 'act' |
                  'link' | 'unlink' | 'subscribe' | 'unsubscribe' | any().

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
    self() ! xl_run,
    process_flag(trap_exit, true),
    S0 = #{entry_time => timestamp(),
           pid => self(),
           status => running,
           links => #{},
           timeout => ?DFL_TIMEOUT},
    S1 = maps:merge(S0, State),
    do_entry(S1).

do_entry(#{entry := Entry} = State) ->
    Entry(State);
do_entry(State) ->
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
handle({sos, Via, Path, Sprig, Command}, State) ->
    relay(Path, Via, Sprig, Command, State);
handle({sos, Via, Sprig, Command}, State) ->
    request(Sprig, Command, Via, State);
handle({sos, Via, Command}, State) ->
    request([], Command, Via, State);
handle({sos, Command}, State) ->
    request([], Command, cast, State);
%%-- process monitors.
handle({'DOWN', _, _, _, _} = Down, State) ->
    case on_down(Down, State) of
        {_, NewState} ->
            {noreply, NewState};
        Stop ->
            Stop
    end;
%%-- drop unknown messages.
handle(_, State) ->
    {noreply, State}.

relay([], Via, Sprig, Command, State) ->
    request(Sprig, Command, Via, State);
relay([Next | Rest], Via, Sprig, Command, State) ->
    case access(get, [links, Next], State) of
        {reply, {ok, Pid}} when is_pid(Pid) ->
            Via1 = append_via(Via),
            Pid ! {sos, Via1, Rest, Sprig, Command},
            {noreply, State};
        _ ->
            reply(Via, {error, badarg}),
            {noreply, State}
    end;
relay(_, Via, _, _, State) ->
    reply(Via, {error, badarg}),
    {noreply, State}.

append_via({Route, Ref}) ->
    make_via(self(), Route, Ref);
append_via(Via) ->
    Via.

make_via(Pid, Route, Ref) when is_list(Route) ->
    {[Pid | Route], Ref};
make_via(Pid, Route, Ref) ->
    {[Pid, Route], Ref}.


on_down({_, Ref, _, _, _} = Down, #{subscribers := Sbs} = State)
  when is_map(Sbs) ->
    case maps:remove(Ref, Sbs) of
        Sbs ->
            on_down_(Ref, Down, State);
        Sbs1 ->
            {noreply, State#{subscribers := Sbs1}}
    end;
on_down(Down, #{subscribers := _} = State) ->
    case request({down, Down}, [subscribers], cast, State) of
        {_, State1} ->
            on_down_(Down, State1);
        Stop ->
            Stop
    end;
on_down(Down, State) ->
    on_down_(Down, State).

on_down_({_, Ref, _, _, _}, #{monitors := M, links := L} = State)
  when is_map(L) ->
    case maps:take(Ref, M) of
        {#{name := Key}, M1} ->
            L1 = maps:remove(Key, L),
            {noreply, State#{monitors := M1, links := L1}};
        error ->
            {noreply, State}
    end;
on_down_(Down, #{links := _}, State) ->
    request({down, Down}, [links, Key], cast, State);
on_down_(_, State) ->
    {noreply, State}.

%%-- Suberscribers
request({subscribe, Pid}, [], Via, State) ->
    subscribe(Pid, Via, State);
request({unsubscribe, Ref}, [], Via, State) ->
    unsubscribe(Ref, Via, State);
%%-- Links
request({link, Label, Pid}, [], Via,  State) ->
    link(Label, Pid, Via, State);
request({unlink, Label}, [], Via, State) ->
    unlink(Label, Via, State);
%%-- Global commands.
request(Command, [], Via, State) ->
    case access(Command, [], State) of
        {reply, Res} ->
            reply(Via, Res),
            {noreply, State};
        {update, Reply, NewS} when (not is_tuple(Command));
                                   element(1, Command) =/= put ->
            reply(Via, Reply),
            {noreply, NewS};
        _ ->
            reply(Via, {error, badarg}),
            {noreply, State}
    end;
%%-- .. Links
request(unlink, [Label], Via, State) ->
    unlink(Label, Via, State);
%%-- Custmoized actions
request(act, [Action], Via, State) ->
    request(Action, [actions], Via, State);
request({act, Args}, [Action], Via, State) ->
    request({Action, Args}, [actions], Via, State);
%%-- Branches and sprig.
request(Command, Sprig, Via, State) ->
    case access(Command, Sprig, State) of
        {reply, Res} ->
            reply(Via, Res),
            {noreply, State};
        {update, Reply, NewState} ->
            reply(Via, Reply),
            {noreply, NewState};
        {action, Func, Route} ->
            case perform(Func, Command, Route, Via, State) of
                {noreply, _} = Result ->
                    Result;
                {noreply, _, _} = Result ->
                    Result;
                {stop, _, _} = Result ->
                    Result;
                {stop, _, _, _} = Result ->
                    Result;
                {reply, Reply, NewState} ->
                    reply(Via, Reply),
                    {noreply, NewState};
                {Reply, NewState} ->
                    reply(Via, Reply),
                    {noreply, NewState};
                {Code, Res, NewState} ->
                    reply(Via, {Code, Res}),
                    {noreply, NewState}
            end;
        {actor, Pid, Sprig} ->
            catch Pid ! {sos, Via, Sprig, Command},
            {noreply, State};
        _ ->
            {error, badarg, State}
    end.

access(get, [], Data) ->
    {reply, {ok, Data}};
access({put, Value}, [], _) ->
    {update, ok, Value};
access(delete, [], _) ->
    {delete, ok};
access({get, Selection}, [], Data)
  when is_list(Selection) andalso is_map(Data) ->
    Value = maps:with(Selection, Data),
    {reply, {ok, Value}};
access({patch, Value}, [], Data)
  when is_map(Value) andalso is_map(Data) ->
    NewData = maps:merge(Data, Value),
    {update, ok, NewData};
access({new, Key, Value}, [], Data) when is_map(Data) ->
    {update, {ok, Key}, Data#{Key => Value}};
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
            {reply, {error, undefined}}
    end;
access(_, Sprig, Data) when is_function(Data) ->
    {action, Data, Sprig};
access(_, Sprig, Data) when is_pid(Data) ->
    {actor, Data, Sprig};
access(_, [], _) ->
    {reply, {error, badarg}};
access(Command, Key, State) ->
    access(Command, [Key], State).

perform(Func, Command, _, _, State) when is_function(Func, 2) ->
    Func(Command, State);
perform(Func, Command, Sprig, _, State) when is_function(Func, 3) ->
    Func(Command, Sprig, State);
perform(Func, Command, Sprig, Via, State) ->
    Func(Command, Sprig, Via, State).

link(Key, Pid, Via, State) ->
    case maps:get(links, State , #{}) of
        Links when is_map(Links) ->
            link(Key, Pid, Links, Via, State);
        Links ->  % function
            request({link, Key, Pid}, [links], Via, State)
    end.

link(Key, Pid, Links, Via, State) ->
    case maps:is_key(Key, Links) of
        true ->
            reply(Via, {error, existed}),
            {noreply, State};
        false ->
            M = maps:get(monitors, State, #{}),
            Ref = monitor(process, Pid),
            NewM = M#{Ref => #{name => Key, process => Pid}},
            NewLinks = Links#{Label => #{process => Pid, monitor => Ref}},
            reply(Via, ok),
            {noreply, State#{links := NewLinks, monitors => NewM}}
    end.

unlink(Key, Via, #{links := Ls, monitors := Ms} = State) when is_map(Ls) ->
    case maps:take(Key, Ls) of
        {#{monitor := Ref}, Ls1} ->
            Ms1 = maps:remove(Ref, Ms),
            demonitor(Ref),
            reply(Via, ok),
            {noreply, State#{links := Ls1, monitors := Ms1}};
        error ->
            reply(Via, {error, undefined}),
            {noreply, State}
    end;
unlink(Key, Via, #{links := Ls} = State) ->
    request(unlink, [links, Key], Via, State);
unlink(_, Via, State) ->
    reply(Via, {error, undefined}),
    {noreply, State}.

subscribe(Pid, Via, State) ->
    case maps:get(subscribers, State , #{}) of
        Sbs when is_map(Sbs) ->
            Ref = monitor(process, Pid),
            reply(Via, {ok, Ref}),
            Sbs1 = Sbs#{Ref => Pid},
            {noreply, State#{subscribers => Sbs1}};
        Sbs ->  % function
            request({subscribe, Pid}, [subscribers], Via, State)
    end.

unsubscribe(Mref, Via, #{subscribers := Sbs} = State) when is_map(Sbs) ->
    demonitor(Mref),
    reply(Via, ok),
    Sbs1 = maps:remove(Mref, Sbs),
    {noreply, State#{subscribers => Sbs1}};
unsubscribe(Mref, Via, #{subscribers := Sbs} = State) ->
    request({unsubscribe, Mref}, [subscribers], Via, State);
unsubscribe(_, Via, State) ->
    reply(Via, {error, undefined}),
    {noreply, State}.

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