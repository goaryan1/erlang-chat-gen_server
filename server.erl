-module(server).
-behaviour(gen_server).

-record(client, {clientSocket, clientName, clientAddress}).
-record(server_status, {listenSocket, counter}).
-include_lib("stdlib/include/qlc.hrl").

-export([start_link/0, accept_clients/0, get_record/1, show_clients/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
 

%%% gen_server callbacks

init([]) ->
    io:format("Initialising Server ~n"),
    {ok, ListenSocket} = gen_tcp:listen(9991, [binary, {active, true}]),
    database_init(),
    ServerStatus = #server_status{listenSocket = ListenSocket, counter=1},
    mnesia:transaction(fun() -> mnesia:write(ServerStatus) end),
    spawn(server, accept_clients, []),
    {ok, ServerStatus}.

database_init() ->
    mnesia:start(),
    mnesia:create_table(client, [{attributes, record_info(fields, client)}]),
    mnesia:create_table(server_status, [{attributes, record_info(fields, server_status)}]).



accept_clients() ->
    [ListenSocket | _] = mnesia:dirty_all_keys(server_status), 
    {atomic, [Row]} = mnesia:transaction(fun() -> mnesia:read(server_status, ListenSocket) end),
    Counter = Row#server_status.counter,
    {ok, ClientSocket} = gen_tcp:accept(ListenSocket),
    ClientName = "User"++integer_to_list(Counter),
    mnesia:transaction(fun() -> mnesia:write(#client{clientSocket = ClientSocket, clientName = ClientName}) end),
    gen_tcp:send(ClientSocket, term_to_binary({success, node(), ClientName})),
    io:format("Client Accepted~n"),
    NewCounter = Counter+1,
    NewRow = Row#server_status{counter = NewCounter},
    mnesia:transaction(fun() -> mnesia:write(NewRow) end),
    accept_clients().

handle_call(Request,From, ServerStatus) ->
    {ClientAddress, _} = From,
    case Request of
        {message, Message} ->
            {client, ClientSocket, ClientName, _} = get_client_info_add(ClientAddress),
            io:format("~p : ~p~n", [ClientName, Message]),
            broadcast({ClientSocket, Message, ClientName}),
            {reply, ok, ServerStatus};
        {username, ClientName} ->
            Record = get_record(ClientName),
            mnesia:transaction(fun() -> mnesia:write(Record#client{clientAddress = ClientAddress}) end),
            {reply, ok, ServerStatus};
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




% -----------------------------------------------------


get_client_info_add(ClientAddress) ->
    F = fun() ->
        qlc:e(qlc:q([M || M <- mnesia:table(client)]))
    end,
    {atomic, ClientList} = mnesia:transaction(F),
    X = lists:filter(fun({client, _Socket, _Name, Address}) ->
        Address == ClientAddress end, ClientList),
    [ClientStatus | _] = X,
    ClientStatus.


get_record(ClientName) ->
    F = fun() -> qlc:e(qlc:q([M || M <- mnesia:table(client)])) end,
    {atomic, Query} = mnesia:transaction(F),
    % io:format("Query : ~p~n",[Query]),
    [Row | _] =  lists:filter(fun({client,_,Name, _}) ->
            Name == ClientName
        end, Query),
    Row.

broadcast({SenderSocket, Message, SenderName}) ->
    % insert_message_database(SenderName, Message, "All"),
    Keys = mnesia:dirty_all_keys(client),
    io:format("Keys : ~p~n",[Keys]),
    lists:foreach(fun(ClientSocket) ->
        % State = get_state(ClientSocket),
        % case State of
        %     online ->
                case ClientSocket/=SenderSocket of
                    true ->
                        case mnesia:dirty_read({client, ClientSocket}) of
                            [_] ->
                                gen_tcp:send(ClientSocket, term_to_binary({message, SenderName, Message}));
                            [] ->
                                io:format("No receiver Found ~n") 
                        end;
                    false -> 
                        ok
                end
        %     _ -> ok
        % end
    end, Keys).


retreive_clients() ->
    F = fun() ->
        qlc:e(qlc:q([M || M <- mnesia:table(client)]))
    end,
    {atomic, ClientList} = mnesia:transaction(F),
    ClientList.

show_clients() ->
    ClientList = retreive_clients(),
    io:format("Connected Clients:~n"),
    lists:foreach(fun(X) ->
        io:format("~p~n", [X]) end, ClientList).
