module API

using Compat, Compat.Dates, DecFP, Missings

let
    global mysql_lib
    if !isdefined(@__MODULE__, :mysql_lib)
        @static Compat.Sys.islinux()   && (lib_choices = ["libmysql.so", "libmysqlclient.so", "libmysqlclient_r.so", "libmariadb.so", "libmysqlclient_r.so.16"])
        @static Compat.Sys.isapple()   && (lib_choices = ["libmysqlclient.dylib", "libperconaserverclient.dylib"])
        @static Compat.Sys.iswindows() && (lib_choices = ["libmysql.dll", "libmariadb.dll"])
        lib = Libdl.find_library(lib_choices)
        const mysql_lib = lib
    end
end

include("consts.jl")

const MEM_ROOT = Ptr{Void}
const LIST = Ptr{Void}
const MYSQL_DATA = Ptr{Void}
const MYSQL_RES = Ptr{Void}
const MYSQL_ROW = Ptr{Ptr{Cchar}}  # pointer to an array of strings
const MYSQL_TYPE = UInt32

"""
The field object that contains the metadata of the table. 
Returned by mysql_fetch_fields API.
"""
struct MYSQL_FIELD
    name::Ptr{Cchar}             ##  Name of column
    org_name::Ptr{Cchar}         ##  Original column name, if an alias
    table::Ptr{Cchar}            ##  Table of column if column was a field
    org_table::Ptr{Cchar}        ##  Org table name, if table was an alias
    db::Ptr{Cchar}               ##  Database for table
    catalog::Ptr{Cchar}          ##  Catalog for table
    def::Ptr{Cchar}              ##  Default value (set by mysql_list_fields)
    field_length::Clong          ##  Width of column (create length)
    max_length::Clong            ##  Max width for selected set
    name_length::Cuint
    org_name_length::Cuint
    table_length::Cuint
    org_table_length::Cuint
    db_length::Cuint
    catalog_length::Cuint
    def_length::Cuint
    flags::Cuint                 ##  Div flags
    decimals::Cuint              ##  Number of decimals in field
    charsetnr::Cuint             ##  Character set
    field_type::Cuint            ##  Type of field. See mysql_com.h for types
    extension::Ptr{Void}
end
nullable(field) = (field.flags & API.NOT_NULL_FLAG) == 0
isunsigned(field) = (field.flags & API.UNSIGNED_FLAG) == 0

"""
Type mirroring MYSQL_TIME C struct.
"""
struct MYSQL_TIME
    year::Cuint
    month::Cuint
    day::Cuint
    hour::Cuint
    minute::Cuint
    second::Cuint
    second_part::Culong
    neg::Cchar
    timetype::Cuint
end

import Base.==

const MYSQL_DATE_FORMAT = Dates.DateFormat("yyyy-mm-dd")
const MYSQL_DATETIME_FORMAT = Dates.DateFormat("yyyy-mm-dd HH:MM:SS")

mysql_time(str) = Dates.Time(map(x->parse(Int, x), split(str, ':'))...)
mysql_date(str) = Dates.Date(str, MYSQL_DATE_FORMAT)
mysql_datetime(str) = Dates.DateTime(contains(str, " ") ? str : "1970-01-01 " * str, MYSQL_DATETIME_FORMAT)
export mysql_time, mysql_date, mysql_datetime

function Base.convert(::Type{DateTime}, mtime::MYSQL_TIME)
    if mtime.year == 0 || mtime.month == 0 || mtime.day == 0
        DateTime(1970, 1, 1,
                 mtime.hour, mtime.minute, mtime.second)
    else
        DateTime(mtime.year, mtime.month, mtime.day,
                 mtime.hour, mtime.minute, mtime.second)
    end
end
Base.convert(::Type{Dates.Time}, mtime::MYSQL_TIME) =
    Dates.Time(mtime.hour, mtime.minute, mtime.second)
Base.convert(::Type{Date}, mtime::MYSQL_TIME) =
    Date(mtime.year, mtime.month, mtime.day)

Base.convert(::Type{MYSQL_TIME}, t::Dates.Time) =
    MYSQL_TIME(0, 0, 0, Dates.hour(t), Dates.minute(t), Dates.second(t), 0, 0, 0)
Base.convert(::Type{MYSQL_TIME}, dt::Date) =
    MYSQL_TIME(Dates.year(dt), Dates.month(dt), Dates.day(dt), 0, 0, 0, 0, 0, 0)

function Base.convert(::Type{MYSQL_TIME}, dtime::DateTime)
    if Dates.year(dtime) == 1970 && Dates.month(dtime) == 1 && Dates.day(dtime) == 1
        MYSQL_TIME(0, 0, 0,
                   Dates.hour(dtime), Dates.minute(dtime), Dates.second(dtime), 0, 0, 0)
    else
        MYSQL_TIME(Dates.year(dtime), Dates.month(dtime), Dates.day(dtime),
                   Dates.hour(dtime), Dates.minute(dtime), Dates.second(dtime), 0, 0, 0)
    end
end

"""
Mirror to MYSQL_BIND struct in mysql_bind.h
"""
struct MYSQL_BIND
    length::Ptr{Culong}
    is_null::Ptr{Cchar}
    buffer::Ptr{Void}
    error::Ptr{Cchar}
    row_ptr::Ptr{Cuchar}
    store_param_func::Ptr{Void}
    fetch_result::Ptr{Void}
    skip_result::Ptr{Void}
    buffer_length::Culong 
    offset::Culong 
    length_value::Culong
    param_number::Cuint
    pack_length::Cuint
    buffer_type::Cint
    error_value::Cchar
    is_unsigned::Cchar
    long_data_used::Cchar
    is_null_value::Cchar
    extension::Ptr{Void}

    function MYSQL_BIND(buff::Ptr{Void}, bufflen, bufftype)
        new(0, 0, buff, C_NULL, C_NULL, 0, 0, 0, convert(Culong, bufflen),
            0, 0, 0, 0, bufftype, 0, 0, 0, 0, C_NULL)
    end
end

function MYSQL_BIND(arr, bufftype)
    MYSQL_BIND(convert(Ptr{Void}, pointer(arr)), sizeof(arr), bufftype)
end

"""
Mirror to MYSQL_ROWS struct in mysql.h
"""
struct MYSQL_ROWS
    next::Ptr{MYSQL_ROWS}
    data::MYSQL_ROW
    length::Culong
end

"""
Mirror to MYSQL_STMT struct in mysql.h
"""
struct MYSQL_STMT # This is different in mariadb header file.
    mem_root::MEM_ROOT
    list::LIST
    mysql::Ptr{Void}
    params::MYSQL_BIND
    bind::MYSQL_BIND
    fields::MYSQL_FIELD
    result::MYSQL_DATA
    data_cursor::MYSQL_ROWS

    affected_rows::Culonglong
    insert_id::Culonglong
    stmt_id::Culong
    flags::Culong
    prefetch_rows::Culong

    server_status::Cuint
    last_errno::Cuint
    param_count::Cuint
    field_count::Cuint
    state::Cuint
    last_error::Ptr{Cchar}
    sqlstate::Ptr{Cchar}
    send_types_to_server::Cint
    bind_param_done::Cint
    bind_result_done::Cuchar
    unbuffered_fetch_cancelled::Cint
    update_max_length::Cint
    extension::Ptr{Cuchar}
end


# function  mysql_library_init(argc=0, argv=C_NULL, groups=C_NULL)
#     return ccall((:mysql_library_init, mysql_lib),
#                  Cint,
#                  (Cint, Ptr{Ptr{UInt8}}, Ptr{Ptr{UInt8}}),
#                  argc, argv, groups)
# end

# function  mysql_library_end()
#     return ccall((:mysql_library_end, mysql_lib),
#                  Void,
#                  (),
#                 )
# end

"""
Initializes the MYSQL object. Must be called before mysql_real_connect.
Memory allocated by mysql_init can be freed with mysql_close.
"""
function mysql_init(mysqlptr::Ptr{Void})
    return ccall((:mysql_init, mysql_lib),
                 Ptr{Void},
                 (Ptr{Cuchar}, ),
                 mysqlptr)
end

"""
Used to connect to database server. Returns a MYSQL handle on success and
C_NULL on failure.
"""
function mysql_real_connect(mysqlptr::Ptr{Void},
                              host::String,
                              user::String,
                              passwd::String,
                              db::String,
                              port::Cuint,
                              unix_socket::String,
                              client_flag::UInt32)

    return ccall((:mysql_real_connect, mysql_lib),
                 Ptr{Void},
                 (Ptr{Void},
                  Ptr{Cuchar},
                  Ptr{Cuchar},
                  Ptr{Cuchar},
                  Ptr{Cuchar},
                  Cuint,
                  Ptr{Cuchar},
                  Culong),
                 mysqlptr,
                 host,
                 user,
                 passwd,
                 db,
                 port,
                 unix_socket,
                 client_flag)
end

function mysql_options(mysqlptr::Ptr{Void},
                        option_type::Cuint,
                        option::Ptr{Void})
    return ccall((:mysql_options, mysql_lib),
                 Cint,
                 (Ptr{Cuchar},
                  Cint,
                  Ptr{Cuchar}),
                 mysqlptr,
                 option_type,
                 option)
end

mysql_options(mysqlptr, option_type, option::String) =
    mysql_options(mysqlptr, option_type, convert(Ptr{Void}, pointer(option)))

function mysql_options(mysqlptr, option_type, option)
    v = [option]
    return mysql_options(mysqlptr, option_type, convert(Ptr{Void}, pointer(v)))
end

"""
Close an opened MySQL connection.
"""
function mysql_close(mysqlptr::Ptr{Void})
    return ccall((:mysql_close, mysql_lib),
                 Void,
                 (Ptr{Cuchar}, ),
                 mysqlptr)
end

"""
Returns the error number of the last API call.
"""
function mysql_errno(mysqlptr::Ptr{Void})
    return ccall((:mysql_errno, mysql_lib),
                 Cuint,
                 (Ptr{Cuchar}, ),
                 mysqlptr)
end

"""
Returns a string of the last error message of the most recent function call.
If no error occured and empty string is returned.
"""
function mysql_error(mysqlptr::Ptr{Void})
    return ccall((:mysql_error, mysql_lib),
                 Ptr{Cuchar},
                 (Ptr{Cuchar}, ),
                 mysqlptr)
end

"""
Executes the prepared query associated with the statement handle.
"""
function mysql_stmt_execute(stmtptr)
    return ccall((:mysql_stmt_execute, mysql_lib),
                 Cint,
                 (Ptr{Cuchar}, ),
                 stmtptr)
end

"""
Closes the prepared statement.
"""
function mysql_stmt_close(stmtptr)
    return ccall((:mysql_stmt_close, mysql_lib),
                 Cchar,
                 (Ptr{Cuchar}, ),
                 stmtptr)
end

function mysql_insert_id(mysqlptr::Ptr{Void})
    return ccall((:mysql_insert_id, mysql_lib),
                 Int64,
                 (Ptr{Cuchar}, ),
                 mysqlptr)
end

"""
Creates the sql string where the special chars are escaped
"""
function mysql_real_escape_string(mysqlptr::Ptr{Void},
                                  to::Vector{Cuchar},
                                  from::String,
                                  length::Culong)
    return ccall((:mysql_real_escape_string, mysql_lib),
                 Cuint,
                 (Ptr{Cuchar},
                  Ptr{Cuchar},
                  Ptr{Cuchar},
                  Culong),
                 mysqlptr,
                 to,
                 from,
                 length)
end

"""
Creates a mysql_stmt handle. Should be closed with mysql_close_stmt
"""
function mysql_stmt_init(mysqlptr::Ptr{Void})
    return ccall((:mysql_stmt_init, mysql_lib),
                 Ptr{MYSQL_STMT},
                 (Ptr{Void}, ),
                 mysqlptr)
end

function mysql_stmt_prepare(stmtptr, s::String)
    return ccall((:mysql_stmt_prepare, mysql_lib),
                 Cint,
                 (Ptr{Void}, Ptr{Cchar}, Culong),
                 stmtptr,      s,        length(s))
end

"""
Returns the error message for the recently invoked statement API
"""
function mysql_stmt_error(stmtptr)
    return ccall((:mysql_stmt_error, mysql_lib),
                 Ptr{Cuchar},
                 (Ptr{Cuchar}, ),
                 stmtptr)
end

"""
Store the entire result returned by the prepared statement in the
bind datastructure provided by mysql_stmt_bind_result.
"""
function mysql_stmt_store_result(stmtptr)
    return ccall((:mysql_stmt_store_result, mysql_lib),
                 Cint,
                 (Ptr{Cuchar}, ),
                 stmtptr)
end

"""
Return the metadata for the results that will be received from
the execution of the prepared statement.
"""
function mysql_stmt_result_metadata(stmtptr)
    return ccall((:mysql_stmt_result_metadata, mysql_lib),
                 MYSQL_RES,
                 (Ptr{MYSQL_STMT}, ),
                 stmtptr)
end

"""
Equivalent of `mysql_num_rows` for prepared statements.
"""
function mysql_stmt_num_rows(stmtptr)
    return ccall((:mysql_stmt_num_rows, mysql_lib),
                 Clong,
                 (Ptr{Cuchar}, ),
                 stmtptr)
end

"""
Equivalent of `mysql_fetch_row` for prepared statements.
"""
function mysql_stmt_fetch(stmtptr)
    return ccall((:mysql_stmt_fetch, mysql_lib),
                 Cint,
                 (Ptr{Cuchar}, ),
                 stmtptr)
end

"""
Bind the returned data from execution of the prepared statement
to a preallocated datastructure `bind`.
"""
function mysql_stmt_bind_result(stmtptr, bind::Ptr{MYSQL_BIND})
    return ccall((:mysql_stmt_bind_result, mysql_lib),
                 Cchar,
                 (Ptr{Cuchar}, Ptr{Cuchar}),
                 stmtptr,
                 bind)
end

function mysql_query(mysqlptr::Ptr{Void}, sql::String)
    return ccall((:mysql_query, mysql_lib),
                 Cchar,
                 (Ptr{Void}, Ptr{Cuchar}),
                 mysqlptr,
                 sql)
end

function mysql_store_result(mysqlptr::Ptr{Void})
    return ccall((:mysql_store_result, mysql_lib),
                 MYSQL_RES,
                 (Ptr{Void}, ),
                 mysqlptr)
end

"""
Returns the field metadata.
"""
function mysql_fetch_fields(results::MYSQL_RES)
    return ccall((:mysql_fetch_fields, mysql_lib),
                 Ptr{MYSQL_FIELD},
                 (MYSQL_RES, ),
                 results)
end


"""
Returns the row from the result set.
"""
function mysql_fetch_row(results::MYSQL_RES)
    return ccall((:mysql_fetch_row, mysql_lib),
                 MYSQL_ROW,
                 (MYSQL_RES, ),
                 results)
end

"""
Frees the result set.
"""
function mysql_free_result(results)
    return ccall((:mysql_free_result, mysql_lib),
                 Ptr{Cuchar},
                 (MYSQL_RES, ),
                 results.ptr)
end

"""
Returns the number of fields in the result set.
"""
function mysql_num_fields(results::MYSQL_RES)
    return ccall((:mysql_num_fields, mysql_lib),
                 Cuint,
                 (MYSQL_RES, ),
                 results)
end

"""
Returns the number of records from the result set.
"""
function mysql_num_rows(results::MYSQL_RES)
    return ccall((:mysql_num_rows, mysql_lib),
                 Clong,
                 (MYSQL_RES, ),
                 results)
end

"""
Returns the # of affected rows in case of insert / update / delete.
"""
function mysql_affected_rows(results::MYSQL_RES)
    return ccall((:mysql_affected_rows, mysql_lib),
                 Culong,
                 (MYSQL_RES, ),
                 results)
end

"""
Set the auto commit mode.
"""
function mysql_autocommit(mysqlptr::Ptr{Void}, mode::Cchar)
    return ccall((:mysql_autocommit, mysql_lib),
                 Cchar, (Ptr{Void}, Cchar),
                 mysqlptr, mode)
end

"""
Used to get the next result while executing multi query. Returns 0 on success
and more results are present. Returns -1 on success and no more results. Returns
positve on error.
"""
function mysql_next_result(mysqlptr::Ptr{Void})
    return ccall((:mysql_next_result, mysql_lib),
                 Cint, (MYSQL_RES, ),
                 mysqlptr)
end

"""
Returns the number of columns for the most recent query on the connection.
"""
function mysql_field_count(mysqlptr::Ptr{Void})
    return ccall((:mysql_field_count, mysql_lib),
                 Cuint, (Ptr{Void}, ), mysqlptr)
end

function mysql_stmt_param_count(stmt)
    return ccall((:mysql_stmt_param_count, mysql_lib),
                 Culong, (Ptr{MYSQL_STMT}, ), stmt)
end

"""
This API is used to bind input data for the parameter markers in the SQL
 statement that was passed to `mysql_stmt_prepare()`. It uses `MYSQL_BIND`
 structures to supply the data. `bind` is the address of an array of `MYSQL_BIND`
 structures. The client library expects the array to contain one element for
 each ? parameter marker that is present in the query.
"""
function mysql_stmt_bind_param(stmt, bind::Ptr{MYSQL_BIND})
    return ccall((:mysql_stmt_bind_param, mysql_lib),
                 Cuchar, (Ptr{MYSQL_STMT}, Ptr{MYSQL_BIND}, ),
                 stmt, bind)
end

"""
Returns number of affected rows for prepared statement. `mysql_stmt_execute` must
 be called before this.
"""
function mysql_stmt_affected_rows(stmt)
    return ccall((:mysql_stmt_affected_rows, mysql_lib),
                 Culong, (Ptr{Void}, ), stmt)
end

end # module