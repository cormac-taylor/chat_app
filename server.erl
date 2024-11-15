-module(server).

-export([start_server/0]).

-include_lib("./defs.hrl").

-spec start_server() -> _.
-spec loop(_State) -> _.
-spec do_join(_ChatName, _ClientPID, _Ref, _State) -> _.
-spec do_leave(_ChatName, _ClientPID, _Ref, _State) -> _.
-spec do_new_nick(_State, _Ref, _ClientPID, _NewNick) -> _.
-spec do_client_quit(_State, _Ref, _ClientPID) -> _NewState.

start_server() ->
    catch(unregister(server)),
    register(server, self()),
    case whereis(testsuite) of
	undefined -> ok;
	TestSuitePID -> TestSuitePID!{server_up, self()}
    end,
    loop(
      #serv_st{
	 nicks = maps:new(), %% nickname map. client_pid => "nickname"
	 registrations = maps:new(), %% registration map. "chat_name" => [client_pids]
	 chatrooms = maps:new() %% chatroom map. "chat_name" => chat_pid
	}
     ).

loop(State) ->
    receive 
	%% initial connection
	{ClientPID, connect, ClientNick} ->
	    NewState =
		#serv_st{
		   nicks = maps:put(ClientPID, ClientNick, State#serv_st.nicks),
		   registrations = State#serv_st.registrations,
		   chatrooms = State#serv_st.chatrooms
		  },
	    loop(NewState);
	%% client requests to join a chat
	{ClientPID, Ref, join, ChatName} ->
	    NewState = do_join(ChatName, ClientPID, Ref, State),
	    loop(NewState);
	%% client requests to join a chat
	{ClientPID, Ref, leave, ChatName} ->
	    NewState = do_leave(ChatName, ClientPID, Ref, State),
	    loop(NewState);
	%% client requests to register a new nickname
	{ClientPID, Ref, nick, NewNick} ->
	    NewState = do_new_nick(State, Ref, ClientPID, NewNick),
	    loop(NewState);
	%% client requests to quit
	{ClientPID, Ref, quit} ->
	    NewState = do_client_quit(State, Ref, ClientPID),
	    loop(NewState);
	{TEST_PID, get_state} ->
	    TEST_PID!{get_state, State},
	    loop(State)
    end.

%% executes join protocol from server perspective
do_join(ChatName, ClientPID, Ref, State) ->
    case maps:find(ChatName, State#serv_st.chatrooms) of
		error ->
			ChatPID = spawn(chatroom, start_chatroom, [ChatName]),
			Updated_State = State#serv_st{registrations = maps:put(ChatName, [], State#serv_st.registrations), 
											  chatrooms = maps:put(ChatName, ChatPID, State#serv_st.chatrooms)};
		{ok, _} ->
			Updated_State = State
	end,
	{ok, ClientNick} = maps:find(ClientPID, Updated_State#serv_st.nicks),
	maps:get(ChatName, Updated_State#serv_st.chatrooms)!{self(), Ref, register, ClientPID, ClientNick},
	Append = fun(L) -> lists:append(L, [ClientPID]) end,
	Updated_State#serv_st{registrations = maps:update_with(ChatName, Append, Updated_State#serv_st.registrations)}.

%% executes leave protocol from server perspective
do_leave(ChatName, ClientPID, Ref, State) ->
	{ok, ChatPID} = maps:find(ChatName, State#serv_st.chatrooms),
	NewList = lists:delete(ClientPID, maps:get(ChatName, State#serv_st.registrations)),
	Updated_State = State#serv_st{registrations = maps:put(ChatName, NewList, State#serv_st.registrations)},
	ChatPID!{self(), Ref, unregister, ClientPID},
	ClientPID!{self(), Ref, ack_leave},
	Updated_State.

%% executes new nickname protocol from server perspective
do_new_nick(State, Ref, ClientPID, NewNick) ->
    case lists:member(NewNick, maps:values(State#serv_st.nicks)) of 
		true ->
			ClientPID!{self(), Ref, err_nick_used},
			State;
		false -> 
			Updated_State = State#serv_st{nicks = maps:put(ClientPID, NewNick, State#serv_st.nicks)},
			PredRelivant = fun(ChatName) ->
				ClientPIDS = maps:get(ChatName, Updated_State#serv_st.registrations),
				lists:member(ClientPID, ClientPIDS)
			end,
			RelivantChatNames = lists:filter(PredRelivant, maps:keys(Updated_State#serv_st.registrations)),
			[ ChatPID!{self(), Ref, update_nick, ClientPID, NewNick} || ChatPID <- RelivantChatNames ],
			ClientPID!{self(), Ref, ok_nick},
			Updated_State
		end.

%% executes client quit protocol from server perspective
do_client_quit(State, Ref, ClientPID) ->
    io:format("server:do_client_quit(...): IMPLEMENT ME~n"),
    State.
