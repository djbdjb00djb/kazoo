%%%-------------------------------------------------------------------
%%% @copyright (C) 2012-2014, 2600Hz, INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%   Karl Anderson
%%%-------------------------------------------------------------------
-module(crossbar_maintenance).

-export([migrate/0
         ,migrate/1
         ,migrate_accounts_data/0
         ,migrate_account_data/1
        ]).

-export([start_module/1]).
-export([stop_module/1]).
-export([running_modules/0]).
-export([refresh/0, refresh/1
         ,flush/0
        ]).
-export([find_account_by_number/1]).
-export([find_account_by_name/1]).
-export([find_account_by_realm/1]).
-export([enable_account/1, disable_account/1]).
-export([promote_account/1, demote_account/1]).
-export([allow_account_number_additions/1, disallow_account_number_additions/1]).
-export([create_account/4]).
-export([create_account/1]).
-export([move_account/2]).
-export([descendants_count/0, descendants_count/1]).
-export([migrate_ring_group_callflow/1]).

-include_lib("crossbar.hrl").

-type input_term() :: atom() | string() | ne_binary().

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec migrate() -> 'no_return'.
migrate() ->
    migrate(whapps_util:get_all_accounts()).

-spec migrate(ne_binaries()) -> 'no_return'.
migrate(Accounts) ->
    _ = migrate_accounts_data(Accounts),

    CurrentModules =
        [wh_util:to_atom(Module, 'true')
         || Module <- crossbar_config:autoload_modules()
        ],

    UpdatedModules = remove_deprecated_modules(CurrentModules, ?DEPRECATED_MODULES),

    add_missing_modules(
      UpdatedModules
      ,[Module
        || Module <- ?DEFAULT_MODULES,
           (not lists:member(Module, CurrentModules))
       ]).

-spec remove_deprecated_modules(atoms(), atoms()) -> atoms().
remove_deprecated_modules(Modules, Deprecated) ->
    case lists:foldl(fun lists:delete/2, Modules, Deprecated) of
        Modules -> Modules;
        Ms ->
            io:format(" removed deprecated modules from autoloaded modules: ~p~n", [Deprecated]),
            crossbar_config:set_autoload_modules(Ms),
            Ms
    end.

-spec migrate_accounts_data() -> 'no_return'.
migrate_accounts_data() ->
    migrate_accounts_data(whapps_util:get_all_accounts()).

-spec migrate_accounts_data(ne_binaries()) -> 'no_return'.
migrate_accounts_data([]) -> 'no_return';
migrate_accounts_data([Account|Accounts]) ->
    _ = migrate_account_data(Account),
    migrate_accounts_data(Accounts).

-spec migrate_account_data(ne_binary()) -> 'no_return'.
migrate_account_data(Account) ->
    _ = cb_clicktocall:maybe_migrate_history(Account),
    _ = migrate_ring_group_callflow(Account),
    'no_return'.

-spec add_missing_modules(atoms(), atoms()) -> 'no_return'.
add_missing_modules(_, []) -> 'no_return';
add_missing_modules(Modules, MissingModules) ->
    io:format("  saving autoload_modules with missing modules added: ~p~n", [MissingModules]),
    crossbar_config:set_autoload_modules(lists:sort(Modules ++ MissingModules)),
    'no_return'.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec refresh() -> 'ok'.
-spec refresh(input_term()) -> 'ok'.

refresh() ->
    io:format("please use whapps_maintenance:refresh().", []).

refresh(Value) ->
    io:format("please use whapps_maintenance:refresh(~p).", [Value]).

-spec flush() -> 'ok'.
flush() ->
    crossbar_config:flush(),
    wh_cache:flush_local(?CROSSBAR_CACHE).

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec start_module(text()) -> 'ok' | {'error', _}.
start_module(Module) ->
    try crossbar:start_mod(Module) of
        _ ->
            Mods = crossbar_config:autoload_modules(),
            crossbar_config:set_default_autoload_modules([wh_util:to_binary(Module)
                                                          | lists:delete(wh_util:to_binary(Module), Mods)
                                                         ]),
            io:format("started and added ~s to autoloaded modules~n", [Module])
    catch
        _E:_R ->
            io:format("failed to start ~s: ~s: ~p~n", [Module, _E, _R])
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec stop_module(text()) -> 'ok' | {'error', _}.
stop_module(Module) ->
    try crossbar:stop_mod(Module) of
        _ ->
            Mods = crossbar_config:autoload_modules(),
            crossbar_config:set_default_autoload_modules(lists:delete(wh_util:to_binary(Module), Mods)),
            io:format("stopped and removed ~s from autoloaded modules~n", [Module])
    catch
        _E:_R ->
            io:format("failed to stop ~s: ~s: ~p~n", [Module, _E, _R])
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec running_modules() -> atoms().
running_modules() -> crossbar_bindings:modules_loaded().

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec find_account_by_number(input_term()) ->
                                    {'ok', ne_binary()} |
                                    {'error', term()}.
find_account_by_number(Number) when not is_binary(Number) ->
    find_account_by_number(wh_util:to_binary(Number));
find_account_by_number(Number) ->
    case wh_number_manager:lookup_account_by_number(Number) of
        {'ok', AccountId, _} ->
            AccountDb = wh_util:format_account_id(AccountId, 'encoded'),
            print_account_info(AccountDb, AccountId);
        {'error', {'not_in_service', AssignedTo}} ->
            AccountDb = wh_util:format_account_id(AssignedTo, 'encoded'),
            print_account_info(AccountDb, AssignedTo);
        {'error', {'account_disabled', AssignedTo}} ->
            AccountDb = wh_util:format_account_id(AssignedTo, 'encoded'),
            print_account_info(AccountDb, AssignedTo);
        {'error', Reason}=E ->
            io:format("failed to find account assigned to number '~s': ~p~n", [Number, Reason]),
            E
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec find_account_by_name(input_term()) ->
                                  {'ok', ne_binary()} |
                                  {'multiples', [ne_binary(),...]} |
                                  {'error', term()}.
find_account_by_name(Name) when not is_binary(Name) ->
    find_account_by_name(wh_util:to_binary(Name));
find_account_by_name(Name) ->
    case whapps_util:get_accounts_by_name(Name) of
        {'ok', AccountDb} ->
            print_account_info(AccountDb);
        {'multiples', AccountDbs} ->
            AccountIds = [begin
                              {'ok', AccountId} = print_account_info(AccountDb),
                              AccountId
                          end || AccountDb <- AccountDbs
                         ],
            {'multiples', AccountIds};
        {'error', Reason}=E ->
            io:format("failed to find account: ~p~n", [Reason]),
            E
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec find_account_by_realm(input_term()) ->
                                   {'ok', ne_binary()} |
                                   {'multiples', [ne_binary(),...]} |
                                   {'error', term()}.
find_account_by_realm(Realm) when not is_binary(Realm) ->
    find_account_by_realm(wh_util:to_binary(Realm));
find_account_by_realm(Realm) ->
    case whapps_util:get_account_by_realm(Realm) of
        {'ok', AccountDb} ->
            print_account_info(AccountDb);
        {'multiples', AccountDbs} ->
            AccountIds = [begin
                              {'ok', AccountId} = print_account_info(AccountDb),
                              AccountId
                          end || AccountDb <- AccountDbs
                         ],
            {'multiples', AccountIds};
        {'error', Reason}=E ->
            io:format("failed to find account: ~p~n", [Reason]),
            E
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec allow_account_number_additions(input_term()) -> 'ok' | 'failed'.
allow_account_number_additions(AccountId) ->
    case update_account(AccountId, <<"pvt_wnm_allow_additions">>, 'true') of
        {'ok', _} ->
            io:format("allowing account '~s' to add numbers~n", [AccountId]);
        {'error', Reason} ->
            io:format("failed to find account: ~p~n", [Reason]),
            'failed'
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec disallow_account_number_additions(input_term()) -> 'ok' | 'failed'.
disallow_account_number_additions(AccountId) ->
    case update_account(AccountId, <<"pvt_wnm_allow_additions">>, 'false') of
        {'ok', _} ->
            io:format("disallowed account '~s' to added numbers~n", [AccountId]);
        {'error', Reason} ->
            io:format("failed to find account: ~p~n", [Reason]),
            'failed'
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec enable_account(input_term()) -> 'ok' | 'failed'.
enable_account(AccountId) ->
    case update_account(AccountId, <<"pvt_enabled">>, 'true') of
        {'ok', _} ->
            io:format("enabled account '~s'~n", [AccountId]);
        {'error', Reason} ->
            io:format("failed to enable account: ~p~n", [Reason]),
            'failed'
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec disable_account(input_term()) -> 'ok' | 'failed'.
disable_account(AccountId) ->
    case update_account(AccountId, <<"pvt_enabled">>, 'false') of
        {'ok', _} ->
            io:format("disabled account '~s'~n", [AccountId]);
        {'error', Reason} ->
            io:format("failed to disable account: ~p~n", [Reason]),
            'failed'
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec promote_account(input_term()) -> 'ok' | 'failed'.
promote_account(AccountId) ->
    case update_account(AccountId, <<"pvt_superduper_admin">>, 'true') of
        {'ok', _} ->
            io:format("promoted account '~s', this account now has permission to change system settings~n", [AccountId]);
        {'error', Reason} ->
            io:format("failed to promote account: ~p~n", [Reason]),
            'failed'
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec demote_account(input_term()) -> 'ok' | 'failed'.
demote_account(AccountId) ->
    case update_account(AccountId, <<"pvt_superduper_admin">>, 'false') of
        {'ok', _} ->
            io:format("promoted account '~s', this account can no longer change system settings~n", [AccountId]);
        {'error', Reason} ->
            io:format("failed to demote account: ~p~n", [Reason]),
            'failed'
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec create_account(input_term(), input_term(), input_term(), input_term()) -> 'ok' | 'failed'.
create_account(AccountName, Realm, Username, Password) when not is_binary(AccountName) ->
    create_account(wh_util:to_binary(AccountName), Realm, Username, Password);
create_account(AccountName, Realm, Username, Password) when not is_binary(Realm) ->
    create_account(AccountName, wh_util:to_binary(Realm), Username, Password);
create_account(AccountName, Realm, Username, Password) when not is_binary(Username) ->
    create_account(AccountName, Realm, wh_util:to_binary(Username), Password);
create_account(AccountName, Realm, Username, Password) when not is_binary(Password) ->
    create_account(AccountName, Realm, Username, wh_util:to_binary(Password));
create_account(AccountName, Realm, Username, Password) ->
    Account = wh_json:from_list([{<<"_id">>, couch_mgr:get_uuid()}
                                 ,{<<"name">>, AccountName}
                                 ,{<<"realm">>, Realm}
                                ]),
    User = wh_json:from_list([{<<"_id">>, couch_mgr:get_uuid()}
                              ,{<<"username">>, Username}
                              ,{<<"password">>, Password}
                              ,{<<"first_name">>, <<"Account">>}
                              ,{<<"last_name">>, <<"Admin">>}
                              ,{<<"priv_level">>, <<"admin">>}
                             ]),
    try
        {'ok', C1} = validate_account(Account, #cb_context{}),
        {'ok', C2} = validate_user(User, C1),
        {'ok', #cb_context{db_name=Db, account_id=AccountId}} = create_account(C1),
        {'ok', _} = create_user(C2#cb_context{db_name=Db, account_id=AccountId}),
        case whapps_util:get_all_accounts() of
            [Db] ->
                _ = promote_account(AccountId),
                _ = allow_account_number_additions(AccountId),
                _ = whistle_services_maintenance:make_reseller(AccountId),
                'ok';
            _Else -> 'ok'
        end,
        'ok'
    catch
        _E:_R ->
            lager:error("crashed creating account: ~s: ~p", [_E, _R]),
            ST = erlang:get_stacktrace(),
            wh_util:log_stacktrace(ST),
            'failed'
    end.



%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec validate_account(wh_json:object(), cb_context:context()) ->
                              {'ok', cb_context:context()} |
                              {'error', wh_json:object()}.
validate_account(JObj, Context) ->
    Payload = [Context#cb_context{req_data=JObj
                                  ,req_nouns=[{?WH_ACCOUNTS_DB, []}]
                                  ,req_verb = ?HTTP_PUT
                                  ,resp_status = 'fatal'
                                 }
              ],
    case crossbar_bindings:fold(<<"v1_resource.validate.accounts">>, Payload) of
        #cb_context{resp_status='success'}=Context1 -> {'ok', Context1};
        #cb_context{resp_status=_S, resp_data=Errors} ->
            io:format("failed to validate account properties(~p): '~s'~n", [_S, wh_json:encode(Errors)]),
            {'error', Errors}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec validate_user(wh_json:object(), cb_context:context()) ->
                           {'ok', cb_context:context()} |
                           {'error', wh_json:object()}.
validate_user(JObj, Context) ->
    Payload = [Context#cb_context{req_data=JObj
                                  ,req_nouns=[{?WH_ACCOUNTS_DB, []}]
                                  ,req_verb = ?HTTP_PUT
                                  ,resp_status = 'fatal'
                                 }
              ],
    case crossbar_bindings:fold(<<"v1_resource.validate.users">>, Payload) of
        #cb_context{resp_status='success'}=Context1 -> {'ok', Context1};
        #cb_context{resp_data=Errors} ->
            io:format("failed to validate user properties: '~s'~n", [wh_json:encode(Errors)]),
            {'error', Errors}
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec create_account(cb_context:context()) ->
                            {'ok', cb_context:context()} |
                            {'error', wh_json:object()}.
create_account(Context) ->
    case crossbar_bindings:fold(<<"v1_resource.execute.put.accounts">>, [Context]) of
        #cb_context{resp_status='success', db_name=AccountDb, account_id=AccountId}=Context1 ->
            io:format("created new account '~s' in db '~s'~n", [AccountId, AccountDb]),
            {'ok', Context1};
        #cb_context{resp_data=Errors} ->
            io:format("failed to create account: '~s'~n", [list_to_binary(wh_json:encode(Errors))]),
            AccountId = wh_json:get_value(<<"_id">>, cb_context:req_data(Context)),
            couch_mgr:db_delete(wh_util:format_account_id(AccountId, 'encoded')),
            {'error', Errors}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec create_user(cb_context:context()) ->
                         {'ok', cb_context:context()} |
                         {'error', wh_json:object()}.
create_user(Context) ->
    case crossbar_bindings:fold(<<"v1_resource.execute.put.users">>, [Context]) of
        #cb_context{resp_status='success', doc=JObj}=Context1 ->
            io:format("created new account admin user '~s'~n", [wh_json:get_value(<<"_id">>, JObj)]),
            {'ok', Context1};
        #cb_context{resp_data=Errors} ->
            io:format("failed to create account admin user: '~s'~n", [list_to_binary(wh_json:encode(Errors))]),
            {'error', Errors}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec update_account(input_term(), ne_binary(), term()) ->
                                  {'ok', wh_json:object()} |
                                  {'error', term()}.
update_account(AccountId, Key, Value) when not is_binary(AccountId) ->
    update_account(wh_util:to_binary(AccountId), Key, Value);
update_account(AccountId, Key, Value) ->
    AccountDb = wh_util:format_account_id(AccountId, 'encoded'),
    Updaters = [fun({'error', _}=E) -> E;
                   ({'ok', J}) ->
                        couch_mgr:save_doc(AccountDb, wh_json:set_value(Key, Value, J))
                end
                ,fun({'error', _}=E) -> E;
                    ({'ok', J}) ->
                         case couch_mgr:lookup_doc_rev(?WH_ACCOUNTS_DB, AccountId) of
                             {'ok', Rev} ->
                                 couch_mgr:save_doc(?WH_ACCOUNTS_DB, wh_json:set_value(<<"_rev">>, Rev, J));
                             {'error', 'not_found'} ->
                                 couch_mgr:save_doc(?WH_ACCOUNTS_DB, wh_json:delete_key(<<"_rev">>, J))
                         end
                 end
               ],
    lists:foldl(fun(F, J) -> F(J) end, couch_mgr:open_doc(AccountDb, AccountId), Updaters).

print_account_info(AccountDb) ->
    AccountId = wh_util:format_account_id(AccountDb, 'raw'),
    print_account_info(AccountDb, AccountId).
print_account_info(AccountDb, AccountId) ->
    case couch_mgr:open_doc(AccountDb, AccountId) of
        {'ok', JObj} ->
            io:format("Account ID: ~s (~s)~n", [AccountId, AccountDb]),
            io:format("  Name: ~s~n", [wh_json:get_value(<<"name">>, JObj)]),
            io:format("  Realm: ~s~n", [wh_json:get_value(<<"realm">>, JObj)]),
            io:format("  Enabled: ~s~n", [not wh_json:is_false(<<"pvt_enabled">>, JObj)]),
            io:format("  System Admin: ~s~n", [wh_json:is_true(<<"pvt_superduper_admin">>, JObj)]);
        {'error', _} ->
            io:format("Account ID: ~s (~s)~n", [AccountId, AccountDb])
    end,
    {'ok', AccountId}.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec move_account(ne_binary(), ne_binary()) -> 'ok'.
move_account(Account, ToAccount) ->
    AccountId = wh_util:format_account_id(Account, 'raw'),
    ToAccountId = wh_util:format_account_id(ToAccount, 'raw'),
    maybe_move_account(AccountId, ToAccountId).

-spec maybe_move_account(ne_binary(), ne_binary()) -> 'ok'.
maybe_move_account(AccountId, AccountId) ->
    io:format("can not move to the same account~n");
maybe_move_account(AccountId, ToAccountId) ->
    case crossbar_util:move_account(AccountId, ToAccountId) of
        {'ok', _} -> io:format("move complete!~n");
        {'error', Reason} ->
            io:format("unable to complete move: ~p~n", [Reason])
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec descendants_count() -> 'ok'.
-spec descendants_count(ne_binary()) -> 'ok'.
descendants_count() ->
    crossbar_util:descendants_count().

descendants_count(AccountId) ->
    crossbar_util:descendants_count(AccountId).

-spec migrate_ring_group_callflow(ne_binary()) -> 'ok'.
migrate_ring_group_callflow(Account) ->
    Callflows = get_ring_group_callflows(Account),
    lists:foreach(fun create_new_ring_group_callflow/1 ,Callflows),
    'ok'.

-spec get_ring_group_callflows(ne_binary()) -> wh_json:objects().
get_ring_group_callflows(Account) ->
    AccountDb = wh_util:format_account_id(Account, 'encoded'),
    case couch_mgr:get_all_results(AccountDb, <<"callflows/crossbar_listing">>) of
        {'error', _M} ->
            io:format("error fetching callflows in ~p ~p~n", [AccountDb, _M]),
            [];
        {'ok', JObjs} ->
            lists:foldl(
                fun(JObj, Acc) ->
                    case
                        {wh_json:get_ne_binary_value([<<"value">>, <<"group_id">>], JObj)
                         ,wh_json:get_ne_binary_value([<<"value">>, <<"type">>], JObj)}
                    of
                        {'undefined', _} -> Acc;
                        {_, 'undefined'} ->
                            Id = wh_json:get_value(<<"id">>, JObj),
                            case couch_mgr:open_doc(AccountDb, Id) of
                                {'ok', CallflowJObj} -> [CallflowJObj|Acc];
                                {'error', _M} ->
                                    io:format("error fetching callflow ~p in ~p ~p~n", [Id, AccountDb, _M]),
                                    Acc
                            end;
                        {_, _} -> Acc
                    end
                end
                ,[]
                ,JObjs
            )
    end.

-spec create_new_ring_group_callflow(wh_json:object()) -> 'ok'.
create_new_ring_group_callflow(JObj) ->
    Props =
        props:filter_undefined([
            {<<"pvt_vsn">>, <<"1">>}
            ,{<<"pvt_type">>, <<"callflow">>}
            ,{<<"pvt_modified">>, wh_util:current_tstamp()}
            ,{<<"pvt_created">>, wh_util:current_tstamp()}
            ,{<<"pvt_account_db">>, wh_json:get_value(<<"pvt_account_db">>, JObj)}
            ,{<<"pvt_account_id">>, wh_json:get_value(<<"pvt_account_id">>, JObj)}
            ,{<<"flow">>, wh_json:from_list([
                    {<<"children">>, wh_json:new()}
                    ,{<<"module">>, <<"ring_group">>}
                ])
             }
            ,{<<"group_id">>, wh_json:get_value(<<"group_id">>, JObj)}
            ,{<<"type">>, <<"baseGroup">>}
        ]),
    set_data_for_callflow(JObj, wh_json:from_list(Props)).


-spec set_data_for_callflow(wh_json:object(), wh_json:object()) -> 'ok'.
set_data_for_callflow(JObj, NewCallflow) ->
    Flow = wh_json:get_value(<<"flow">>, NewCallflow),
    case wh_json:get_value([<<"flow">>, <<"module">>], JObj) of
        <<"ring_group">> ->
            Data = wh_json:get_value([<<"flow">>, <<"data">>], JObj),
            NewFlow = wh_json:set_value(<<"data">>, Data, Flow),
            set_number_for_callflow(JObj, wh_json:set_value(<<"flow">>, NewFlow, NewCallflow));
        <<"record_call">> ->
            Data = wh_json:get_value([<<"flow">>, <<"children">>, <<"_">>, <<"data">>], JObj),
            NewFlow = wh_json:set_value(<<"data">>, Data, Flow),
            set_number_for_callflow(JObj, wh_json:set_value(<<"flow">>, NewFlow, NewCallflow));
        _ ->
            io:format("unable to find data for ~p aborting...~n", [wh_json:get_value(<<"_id">>, JObj)])
    end.

-spec set_number_for_callflow(wh_json:object(), wh_json:object()) -> 'ok'.
set_number_for_callflow(JObj, NewCallflow) ->
    Number = <<"group_", (wh_util:to_binary(wh_util:now_ms(erlang:now())))/binary>>,
    Numbers = [Number],
    set_name_for_callflow(JObj, wh_json:set_value(<<"numbers">>, Numbers, NewCallflow)).

-spec set_name_for_callflow(wh_json:object(), wh_json:object()) -> 'ok'.
set_name_for_callflow(JObj, NewCallflow) ->
    Name = wh_json:get_value(<<"name">>, JObj),
    NewName = binary:replace(Name, <<"Ring Group">>, <<"Base Group">>),
    set_ui_metadata(JObj, wh_json:set_value(<<"name">>, NewName, NewCallflow)).

-spec set_ui_metadata(wh_json:object(), wh_json:object()) -> 'ok'.
set_ui_metadata(JObj, NewCallflow) ->
    MetaData = wh_json:get_value(<<"ui_metadata">>, JObj),
    NewMetaData = wh_json:set_value(<<"version">>, <<"v3.19">>, MetaData),
    save_new_ring_group_callflow(JObj, wh_json:set_value(<<"ui_metadata">>, NewMetaData, NewCallflow)).

-spec save_new_ring_group_callflow(wh_json:object(), wh_json:object()) -> 'ok'.
save_new_ring_group_callflow(JObj, NewCallflow) ->
    AccountDb = wh_json:get_value(<<"pvt_account_db">>, JObj),
    Name = wh_json:get_value(<<"name">>, NewCallflow),
    case check_if_callflow_exist(AccountDb, Name) of
        'true' ->
            io:format("unable to save new callflow ~p in ~p already exist~n", [Name, AccountDb]);
        'false' ->
            case couch_mgr:save_doc(AccountDb, NewCallflow) of
                {'error', _M} ->
                    io:format("unable to save new callflow (old:~p) in ~p aborting...~n", [wh_json:get_value(<<"_id">>, JObj), AccountDb]);
                {'ok', NewJObj} -> update_old_ring_group_callflow(JObj, NewJObj)
            end
    end.

-spec check_if_callflow_exist(ne_binary(), ne_binary()) -> boolean().
check_if_callflow_exist(Account, Name) ->
    AccountDb = wh_util:format_account_id(Account, 'encoded'),
    case couch_mgr:get_all_results(AccountDb, <<"callflows/crossbar_listing">>) of
        {'error', _M} ->
            io:format("error fetching callflows in ~p ~p~n", [AccountDb, _M]),
            'true';
        {'ok', JObjs} ->
            lists:foldl(
                fun(JObj, Acc) ->
                    case wh_json:get_value([<<"value">>, <<"name">>], JObj) =:= Name of
                        'true' -> 'true';
                        'false' -> Acc
                    end
                end
                ,'false'
                ,JObjs
            )
    end.

-spec update_old_ring_group_callflow(wh_json:object(), wh_json:object()) -> 'ok'.
update_old_ring_group_callflow(JObj, NewCallflow) ->
    Routines = [
        fun update_old_ring_group_type/2
        ,fun update_old_ring_group_metadata/2
        ,fun update_old_ring_group_flow/2
        ,fun save_old_ring_group/2
    ],
    lists:foldl(fun(F, J) -> F(J, NewCallflow) end, JObj, Routines).

-spec update_old_ring_group_type(wh_json:object(), wh_json:object()) -> wh_json:object().
update_old_ring_group_type(JObj, _NewCallflow) ->
    wh_json:set_value(<<"type">>, <<"userGroup">>, JObj).

-spec update_old_ring_group_metadata(wh_json:object(), wh_json:object()) -> wh_json:object().
update_old_ring_group_metadata(JObj, _NewCallflow) ->
    MetaData = wh_json:get_value(<<"ui_metadata">>, JObj),
    NewMetaData = wh_json:set_value(<<"version">>, <<"v3.19">>, MetaData),
    wh_json:set_value(<<"ui_metadata">>, NewMetaData, JObj).

-spec update_old_ring_group_flow(wh_json:object(), wh_json:object()) -> wh_json:object().
update_old_ring_group_flow(JObj, NewCallflow) ->
    Data = wh_json:from_list([{<<"id">>, wh_json:get_value(<<"_id">>, NewCallflow)}]),
    case wh_json:get_value([<<"flow">>, <<"module">>], JObj) of
        <<"ring_group">> ->
            Flow = wh_json:get_value(<<"flow">>, JObj),
            NewFlow = wh_json:set_values([{<<"data">>, Data}, {<<"module">>, <<"callflow">>}], Flow),
            wh_json:set_value(<<"flow">>, NewFlow, JObj);
        <<"record_call">> ->
            ChFlow = wh_json:get_value([<<"flow">>, <<"children">>, <<"_">>], JObj),
            ChNewFlow = wh_json:set_values([{<<"data">>, Data}, {<<"module">>, <<"callflow">>}], ChFlow),
            Children = wh_json:set_value(<<"_">>, ChNewFlow, wh_json:get_value([<<"flow">>, <<"children">>], JObj)),
            Flow = wh_json:set_value(<<"children">>, Children, wh_json:get_value(<<"flow">>, JObj)),
            wh_json:set_value(<<"flow">>, Flow, JObj)
    end.

-spec save_old_ring_group(wh_json:object(), wh_json:object()) -> 'ok'.
save_old_ring_group(JObj, NewCallflow) ->
    AccountDb = wh_json:get_value(<<"pvt_account_db">>, JObj),
    case couch_mgr:save_doc(AccountDb, JObj) of
        {'error', _M} ->
            L = [wh_json:get_value(<<"_id">>, JObj), AccountDb, wh_json:get_value(<<"_id">>, NewCallflow)],
            io:format("unable to save callflow ~p in ~p, removing new one (~p)~n", L),
            {'ok', _} = couch_mgr:del_doc(AccountDb, NewCallflow),
            'ok';
        {'ok', _} -> 'ok'
    end.
