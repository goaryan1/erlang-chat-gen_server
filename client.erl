-module(client).
 
-export([start/0, listen_loop/1, send_message/0]).
-record(client_status, {name, serverSocket, startPid, serverNode}).
% -define(SERVER, server).
 
start() ->
    io:format("?MODULE = ~p~n", [?MODULE]),
    io:format("Connecting to server...~n"),
    {ok, Socket} = gen_tcp:connect('localhost', 9991, [binary, {active, true}]),
    gen_tcp:recv(Socket, 0),
    receive
        {tcp, Socket, BinaryData} ->
            Data = erlang:binary_to_term(BinaryData),
            {success ,ServerNode, ClientName} = Data,
            io:format("Successfully joined with Username : ~p~n",[ClientName]),
            ClientStatus = #client_status{name = ClientName, serverSocket = Socket, startPid = self(), serverNode = ServerNode},
            SpawnedPid = spawn(fun() -> listen_loop(ClientStatus) end),
            put(spawnedPid, SpawnedPid),
            % listen_loop(ClientStatus),
            ok;
        {tcp_closed, Socket} ->
            io:format("Connection closed~n")
    end.
 
listen_loop(ClientStatus) ->
    Socket = ClientStatus#client_status.serverSocket,
    StartPid = ClientStatus#client_status.startPid,
    ServerNode = ClientStatus#client_status.serverNode,
    receive
        {tcp, Socket, BinaryData} ->
            Data = binary_to_term(BinaryData),
            case Data of
                _ ->
                    io:format("Undefined message received~n")
            end;
        {tcp_closed, Socket} ->
            io:format("Connection closed~n"),
            ok;
        {StartPid, Data} ->
            case Data of
                {message, Message} ->
                    Request = {message, Message},
                    % ServerNode = ,
                    Response = gen_server:call({server, ServerNode}, Request),
                    io:format("~p~n", [Response]),
                    ok;
                    % gen_tcp:send(Socket, BinaryData);
                _ ->
                    io:format("Undefined internal message received~n")
            end
    end,
 
    listen_loop(ClientStatus).
 
send_message() ->
    Message = string:trim(io:get_line("Enter message: ")),
    StartPid = self(),
    SpawnedPid = get(spawnedPid),
    SpawnedPid ! {StartPid, {message, Message}},
    ok.
 
 