-ifndef(TELETYPE_HRL).
-include_lib("whistle/include/wh_types.hrl").
-include_lib("whistle/include/wh_log.hrl").
-include_lib("whistle/include/wh_databases.hrl").

-define(APP_NAME, <<"teletype">>).
-define(APP_VERSION, <<"0.0.1">> ).

-define(PVT_TYPE, <<"notification">>).

-define(NOTIFY_CONFIG_CAT, <<"notify">>).

-type mime_tuples() :: [mimemail:mimetuple(),...] | [].

%% {ContentType, Filename, Content}
-type attachment() :: {ne_binary(), ne_binary(), binary()}.
-type attachments() :: [attachment(),...] | [].

-define(MACRO_VALUE(Key, Label, Name, Description)
        ,{Key
          ,wh_json:from_list([{<<"i18n_label">>, Label}
                              ,{<<"friendly_name">>, Name}
                              ,{<<"description">>, Description}
                             ])
         }).

-define(CALLER_ID_MACROS
        ,[?MACRO_VALUE(<<"caller_id.number">>, <<"caller_id_number">>, <<"Caller ID Number">>, <<"Number of the caller">>)
          ,?MACRO_VALUE(<<"caller_id.name">>, <<"caller_id_name">>, <<"Caller ID Name">>, <<"Name of the caller">>)
         ]).

-define(CALLEE_ID_MACROS
        ,[?MACRO_VALUE(<<"callee_id.number">>, <<"callee_id_number">>, <<"Callee ID Number">>, <<"Number of the callee">>)
          ,?MACRO_VALUE(<<"callee_id.name">>, <<"callee_id_name">>, <<"Callee ID Name">>, <<"Name of the callee">>)
         ]).

-define(DATE_CALLED_MACROS
        ,[?MACRO_VALUE(<<"date_called.utc">>, <<"date_called_utc">>, <<"Date (UTC)">>, <<"When was the voicemail left (UTC)">>)
          ,?MACRO_VALUE(<<"date_called.local">>, <<"date_called_local">>, <<"Date">>, <<"When was the voicemail left (Local time)">>)
         ]).

-define(FROM_MACROS
        ,[?MACRO_VALUE(<<"from.user">>, <<"from_user">>, <<"From User">>, <<"SIP From Username">>)
          ,?MACRO_VALUE(<<"from.realm">>, <<"from_realm">>, <<"From Realm">>, <<"SIP From Realm">>)
         ]).

-define(TO_MACROS
        ,[?MACRO_VALUE(<<"to.user">>, <<"to_user">>, <<"To User">>, <<"SIP To Username">>)
          ,?MACRO_VALUE(<<"to.realm">>, <<"to_realm">>, <<"To Realm">>, <<"SIP To Realm">>)
         ]).

-define(DEFAULT_CALL_MACROS
        ,?CALLER_ID_MACROS
        ++ ?CALLEE_ID_MACROS
        ++ ?DATE_CALLED_MACROS
        ++ ?FROM_MACROS
        ++ ?TO_MACROS
       ).

-define(TELETYPE_HRL, 'true').
-endif.
