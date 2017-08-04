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

%% Explicit Identify (available options: filename, width, height, type)
-spec identify_explicit(File :: file:filename_all(), Options :: [term()]) ->
    {'ok', Props :: maps:map()} | {'error', Reason :: atom()}.

identify_explicit(File, Options) ->
    Template = "identify -format :format_string :file",
    TemplateOpts = [
        {file, stringify(File)},
        {format_string, identify_format_string(Options)}
    ],
    case gm_util:exec_cmd("gm " ++ bind_data(Template, TemplateOpts, [escape])) of
        {0, Result} -> {ok, parse_identify_explicit(Result)};
        {_, Result} -> cmd_error(Result)
    end.

%% Identify
-spec identify(File :: file:filename_all(), Options :: [term()]) ->
    {'ok', Result :: string()} | {'error', Reason :: atom()}.

identify(File, Options) ->
    Template = "identify {{options}} :file",
    TemplateOpts = [{file, stringify(File)}],
    exec_cmd(Template, TemplateOpts, Options).

%% Composite
-spec composite(File :: file:filename_all(), BaseFile :: file:filename_all(), Converted :: file:filename_all(), Options :: [term()]) ->
    'ok' | {'error', Reason :: atom()}.

composite(File, BaseFile, Converted, Options) ->
    Template = "composite {{options}} :input_file :output_file",
    TemplateOpts = [
        {input_file, stringify(File) ++ "\" \"" ++ stringify(BaseFile)},
        {output_file, stringify(Converted)}
    ],
    Result = exec_cmd(Template, TemplateOpts, Options),
    omit_output(Result).

%% Convert
-spec convert(File :: file:filename_all(), Converted :: file:filename_all()) ->
    'ok' | {'error', Reason :: atom()}.

convert(File, Converted) ->
    convert(File, Converted, [], []).

-spec convert(File :: file:filename_all(), Converted :: file:filename_all(), Options :: [term()]) ->
    'ok' | {'error', Reason :: atom()}.

convert(File, Converted, Options) ->
    convert(File, Converted, Options, []).

-spec convert(File :: file:filename_all(), Converted :: file:filename_all(), Options :: [term()], OutputOptions :: [term()]) ->
    'ok' | {'error', Reason :: atom()}.

convert(File, Converted, Options, OutputOptions) ->
    Template = "convert {{options}} :input_file {{output_options}} :output_file",
    TemplateOpts = [
        {input_file, stringify(File)},
        {output_file, stringify(Converted)}
    ],
    Result = exec_cmd(Template, TemplateOpts, Options, OutputOptions),
    omit_output(Result).

%% Mogrify
-spec mogrify(File :: file:filename_all(), Options :: [term()]) ->
    'ok' | {'error', Reason :: atom()}.

mogrify(File, Options) ->
    Template = "mogrify {{options}} :file",
    TemplateOpts = [{file, stringify(File)}],
    Result = exec_cmd(Template, TemplateOpts, Options),
    omit_output(Result).

%% Montage
-spec montage(Files :: [file:filename_all(), ...], Converted :: file:filename_all(), Options :: [term()]) ->
    'ok' | {'error', Reason :: atom()}.

montage(Files, Converted, Options) ->
    Template = "montage {{options}} :input_file :output_file",
    TemplateOpts = [
        {input_file, string:join([stringify(File) || File <- Files], "\" \"")},
        {output_file, stringify(Converted)}
    ],
    Result = exec_cmd(Template, TemplateOpts, Options),
    omit_output(Result).

%% Version
-spec version() ->
    {'ok', Version :: string()} | {'error', Reason :: atom()}.

version() ->
    case exec_cmd("version", [], []) of
        {ok, Version} -> {ok, parse_version(Version)};
        {error, Reason} -> {error, Reason}
    end.

%% Internal functions

%% Run a command based on a template and passed in options
exec_cmd(Template, ExtraOptions, Options) ->
    exec_cmd(Template, ExtraOptions, Options, []).

exec_cmd(Template, ExtraOptions, Options, OutputOptions) ->
    OptString = opt_string(Options),
    OutOptString = opt_string(OutputOptions),
    PreParsed = bind_data(Template, ExtraOptions, [escape]),
    CmdString = re:replace(PreParsed, "{{options}}", OptString, [{return, list}]),
    Command = re:replace(CmdString, "{{output_options}}", OutOptString, [{return, list}]),
    Result = gm_util:exec_cmd(lists:concat(["gm ", Command])),
    parse_result(Result).

%% Create a format string from the passed in options
identify_format_string(Options) ->
    Parts = [kv_string(Option) || Option <- Options],
    string:join(Parts, "--SEP--") ++ "\n".

%% Parse the result of the identify command using "explicit"
parse_identify_explicit(Str) ->
    [Str1|_] = re:split(Str, "\n", [{return, list}]),
    Stripped = re:replace(Str1, "\r", "", [{return, list}]),
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

%% Parse an error coming from an executed command
cmd_error(Msg) ->
    Errors = [
        {"command not found", command_not_found},
        {"No such file", file_not_found},
        {"Request did not return an image", no_image_returned},
        {"unable to open image", unable_to_open}
    ],
    parse_error(Msg, Errors).

%% Run through each error, checking for a match.
parse_error(_, []) ->
    {error, unknown_error};
parse_error(Cmd, [{ErrorDescription, Error}|Errors]) ->
    case re:run(Cmd, ErrorDescription) of
        {match, _} -> {error, Error};
        _ -> parse_error(Cmd, Errors)
    end.

%% Return ok if successful, otherwise return a useful error
parse_result(Result) ->
    case Result of
        {0, Msg} -> {ok, Msg};
        {_, Msg} -> cmd_error(Msg)
    end.

parse_version(Str) ->
    case string:str(Str, " http://") of
        0 -> Str;
        Index -> string:substr(Str, 1, Index - 1)
    end.

omit_output(ok) -> ok;
omit_output({ok, _}) -> ok;
omit_output(Other) -> Other.