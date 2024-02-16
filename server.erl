-module(server).
-behaviour(gen_server).

-record(client, {clientSocket, clientName}).
-record(server_status, {listenSocket, counter}).

-export([start_link/0, accept_clients/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).
 
-define(SERVER, ?MODULE).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
 

%%% gen_server callbacks

init([]) ->
    io:format("Initialising Server ~n"),
    {ok, ListenSocket} = gen_tcp:listen(9991, [binary, {active, true}]),
    database_init(),
    ServerStatus = #server_status{listenSocket = ListenSocket, counter=1},
    spawn(server, accept_clients, [ServerStatus]),
    {ok, ServerStatus}.

database_init() ->
    mnesia:start(),
    mnesia:create_table(client, [{attributes, record_info(fields, client)}]),
    mnesia:create_table(server_status, [{attributes, record_info(fields, server_status)}]).



accept_clients(ServerStatus) ->
    ListenSocket = ServerStatus#server_status.listenSocket,
    Counter = ServerStatus#server_status.counter,
    {ok, ClientSocket} = gen_tcp:accept(ListenSocket),
    ClientName = "User"++integer_to_list(Counter),
    mnesia:transaction(fun() -> mnesia:write(#client{clientSocket = ClientSocket, clientName = ClientName}) end),
    gen_tcp:send(ClientSocket, term_to_binary({success, node(), ClientName})),
    io:format("Client Accepted~n"),
    NewCounter = Counter+1,
    {atomic, [Row]} = mnesia:transaction(fun() -> mnesia:read({server_status, ListenSocket}) end),
    NewRow = Row#server_status{counter = NewCounter},
    mnesia:transaction(fun() -> mnesia:write(NewRow) end),
    accept_clients(ServerStatus).

handle_call(Request, _From, ServerStatus) ->
    case Request of
        {message, Message} ->
            io:format("~p : ~p~n", [_From, Message]),
            Reply = "Message received at server",
            {reply, Reply, ServerStatus};
        _ -> 
            ok
    end.

handle_cast(_Msg, State) ->
    {noreply, State}.
 
handle_info(_Info, State) ->
    {noreply, State}.
 
terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


