-module(gm_util).

%% Exported Functions
-export([
    exec_cmd/1
]).

%% API
-spec exec_cmd(Command :: file:filename_all()) ->
    {ExitCode :: integer(), Output :: string()}.

exec_cmd(Command) ->
    Port = open_port({spawn, Command}, [stream, in, eof, hide, exit_status]),
    get_data(Port, []).

%% Internal function
get_data(Port, Sofar) ->
    receive
        {Port, {data, Bytes}} ->
            get_data(Port, [Sofar|Bytes]);
        {Port, eof} ->
            Port ! {self(), close},
            receive {Port, closed} -> true end,
            ExitCode = receive {Port, {exit_status, Code}} -> Code end,
            {ExitCode, lists:flatten(Sofar)}
    end.