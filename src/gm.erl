%%% Functions for interacting with GraphicsMagick

-module(gm).

-export([
    identify_explicit/2,
    identify/2,
    composite/4,
    convert/2,
    convert/3,
    convert/4,
    mogrify/2,
    montage/3,
    version/0
]).

%% API

%% Explicit Identify
%%
%% Get explicit image characteristics in a list to be parsed by proplists:get_value
%%
%% Example:
%%
%%    identify_explicit("my.jpg", [filename, width, height, type]}).
%%
%% Which returns a map of characteristics to be retrived with maps:get
%%

-spec identify_explicit(File :: file:filename_all(), Options :: [term()]) ->
    {'ok', Props :: maps:map()} | {'error', Reason :: atom()}.

identify_explicit(File, Options) ->
    Template = "identify -format :format_string :file",
    TemplateOpts = [
        {file, stringify(File)},
        {format_string, identify_format_string(Options)}
    ],
    Result = os:cmd("gm " ++ bind_data(Template, TemplateOpts, [escape])),
    case cmd_error(Result) of
        {error, Reason} -> {error, Reason};
        no_error -> parse_identify_explicit(Result)
    end.

%% Identify
identify(File, Options) ->
    Template = "identify {{options}} :file",
    TemplateOpts = [{file, stringify(File)}],
    exec_cmd(Template, TemplateOpts, Options).

%% Composite
composite(File, BaseFile, Converted, Options) ->
    Template = "composite {{options}} :input_file :output_file",
    TemplateOpts = [{input_file, File ++ "\" \"" ++ BaseFile}, {output_file, Converted}],
    exec_cmd(Template, TemplateOpts, Options).

%% Convert
convert(File, Converted) ->
    convert(File, Converted, [], []).

convert(File, Converted, Options) ->
    convert(File, Converted, Options, []).

convert(File, Converted, Options, OutputOptions) ->
    Template = "convert {{options}} :input_file {{output_options}} :output_file",
    TemplateOpts = [{input_file, File}, {output_file, Converted}],
    exec_cmd(Template, TemplateOpts, Options, OutputOptions).

%% Mogrify
mogrify(File, Options) ->
    Template = "mogrify {{options}} :file",
    TemplateOpts = [{file, File}],
    exec_cmd(Template, TemplateOpts, Options).

%% Montage
montage(Files, Converted, Options) ->
    Template = "montage {{options}} :input_file :output_file",
    TemplateOpts = [{input_file, string:join(Files, "\" \"")}, {output_file, Converted}],
    exec_cmd(Template, TemplateOpts, Options).

%% Version
version() ->
    Template = "version",
    exec_cmd(Template).

%% Internal functions

%% Run an os:cmd based on a template without options
exec_cmd(Template) ->
    os:cmd(lists:concat(["gm ", Template])).

%% Run an os:cmd based on a template and passed in options
exec_cmd(Template, ExtraOptions, Options) ->
    exec_cmd(Template, ExtraOptions, Options, []).

exec_cmd(Template, ExtraOptions, Options, OutputOptions) ->
    OptString = opt_string(Options),
    OutOptString = opt_string(OutputOptions),
    PreParsed = bind_data(Template, ExtraOptions, [escape]),
    CmdString = re:replace(PreParsed, "{{options}}", OptString, [{return, list}]),
    Command = re:replace(CmdString, "{{output_options}}", OutOptString, [{return, list}]),
    Cmd = os:cmd(lists:concat(["gm ", Command])),
    parse_result(Cmd).

%% Create a format string from the passed in options
identify_format_string(Options) ->
    Parts = [kv_string(Option) || Option <- Options],
    string:join(Parts, "--SEP--").

%% Parse the result of the identify command using "explicit"
parse_identify_explicit(Str) ->
    Stripped = re:replace(Str, "\r", "", [{return, list}]),
    Stripped1 = re:replace(Stripped, "\n", "", [{return, list}]),
    FormatParts = re:split(Stripped1, "--SEP--", [{return, list}]),
    ParsedParts = [part_to_tuple(X) || X <- FormatParts],
    maps:from_list(ParsedParts).

%% Create a k:v format string to simplify parsing
kv_string(Option) ->
    string:join([atom_to_list(Option), gm_format_char:val(Option)], ": ").

%% Convert an identify -format response to a list of k/v pairs
part_to_tuple(X) ->
    [K, V] = re:split(X, ": ", [{return, list}]),
    K1 = list_to_atom(K),
    {K1, converted_value(K1, V)}.

%% Conversions for passed options
converted_value(width, V) ->
    list_to_integer(V);
converted_value(height, V) ->
    list_to_integer(V);
converted_value(_Label, V) ->
    V.

%% Build the option part of the command string from a list of options
opt_string(Options) ->
    opt_string("", Options).

opt_string(OptString, []) ->
    OptString;
opt_string(OptString, [Option|RestOptions]) ->
    NewOptString = case gm_options:opt(Option) of
        {Switch, Template, Data} ->
            Parsed = lists:concat(["\"", bind_data(Template, Data, []), "\""]),
            string:join([OptString, Switch, Parsed], " ");
        {Switch} ->
            string:join([OptString, Switch], " ")
    end,
    opt_string(NewOptString, RestOptions).

%% Bind data to a command template
bind_data(Template, [{Key, Value}|Rest], Options) ->
    Search = lists:concat([":", atom_to_list(Key)]),
    Replace = case Options of
        [escape] -> lists:concat(["\"", stringify(Value), "\""]);
        _ -> Value
    end,
    NewTemplate = re:replace(Template, Search, stringify(Replace), [{return, list}]),
    bind_data(NewTemplate, Rest, Options);
bind_data(Template, [], _Options) ->
    Template.

%% Convert the given value to a string
stringify(Int) when is_integer(Int) ->
    integer_to_list(Int);
stringify(Atom) when is_atom(Atom) ->
    atom_to_list(Atom);
stringify(Binary) when is_binary(Binary) ->
    binary_to_list(Binary);
stringify(Value) ->
    Value.

%% Parse an error coming from an executed os:cmd
cmd_error(Cmd) ->
    Errors = [
        {"command not found", command_not_found},
        {"No such file", file_not_found},
        {"Request did not return an image", no_image_returned},
        {"unable to open image", unable_to_open}
    ],
    parse_error(Cmd, Errors).

%% Run through each error, checking for a match.
%% Return `no_error` when there are no more possibilities.
parse_error(_, []) ->
    no_error;
parse_error(Cmd, [{ErrorDescription, Error}|Errors]) ->
    case re:run(Cmd, ErrorDescription) of
        {match, _} -> {error, Error};
        _ -> parse_error(Cmd, Errors)
    end.

%% Return ok if successful, otherwise return a useful error
parse_result(Result) ->
    case cmd_error(Result) of
        {error, Msg} ->
            {error, Msg};
        no_error ->
            case Result of
                [] -> ok;
                Msg -> {error, Msg}
            end
    end.
