-module(gm_test).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

gm_test_() ->
    [
        {"Returns a file_not_found error", fun test_file_not_found/0},
        {"Gets explicit image info", fun test_image_info/0},
        {"Doesn\"t get hacked", fun test_escapes_hacking/0}
    ].

test_file_not_found() ->
    ?assertMatch({error, file_not_found}, identify("doesntexist.jpg", [])).

test_image_info() ->
    Img = "sandbox/cyberbrain.jpg",
    Info = identify_explicit(Img, [width]),
    ?assertMatch(600, proplists:get_value(width, Info)).

test_escapes_hacking() ->
    mogrify("baz", [{output_directory, "$(touch hackingz)"}]),
    ?assertMatch(false, filelib:is_file("hackingz")).

-endif.
