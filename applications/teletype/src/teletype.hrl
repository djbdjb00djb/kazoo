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

-define(TELETYPE_HRL, 'true').
-endif.
