function quoteid(str)
    # avoid double quoting
    if str[1] == '`' && str[end] == '`'
        return str
    else
        return string('`', str, '`')
    end
end

sqltype(::Type{Union{T, Missing}}) where {T} = sqltype(T)
sqltype(T) = get(SQLTYPES, T, "VARCHAR(255)")

const SQLTYPES = Dict{Type, String}(
    Int8 => "TINYINT",
    Int16 => "SMALLINT",
    Int32 => "INTEGER",
    Int64 => "BIGINT",
    UInt8 => "TINYINT UNSIGNED",
    UInt16 => "SMALLINT UNSIGNED",
    UInt32 => "INTEGER UNSIGNED",
    UInt64 => "BIGINT UNSIGNED",
    Float32 => "FLOAT",
    Float64 => "DOUBLE",
    DecFP.Dec64 => "NUMERIC(16, 6)",
    DecFP.Dec128 => "NUMERIC(35, 6)",
    Bool => "BOOL",
    Vector{UInt8} => "BLOB",
    String => "VARCHAR(255)",
    Date => "DATE",
    Time => "TIME",
    DateTime => "DATETIME",
    DateAndTime => "DATETIME(6)",
)

checkdupnames(names) = length(unique(map(x->lowercase(String(x)), names))) == length(names) || error("duplicate case-insensitive column names detected; sqlite doesn't allow duplicate column names and treats them case insensitive")

function createtable(conn::Connection, nm::AbstractString, sch::Tables.Schema; debug::Bool=false, quoteidentifiers::Bool=true, createtableclause::AbstractString="CREATE TABLE", columnsuffix=Dict())
    names = sch.names
    checkdupnames(names)
    types = [sqltype(T) for T in sch.types]
    columns = (string(quoteidentifiers ? quoteid(String(names[i])) : names[i], ' ', types[i], ' ', get(columnsuffix, names[i], "")) for i = 1:length(names))
    debug && @info "executing create table statement: `$createtableclause $nm ($(join(columns, ", ")))`"
    return DBInterface.execute(conn, "$createtableclause $nm ($(join(columns, ", ")))")
end

"""
    MySQL.load(table, conn, name; append=true, quoteidentifiers=true, limit=typemax(Int64), createtableclause=nothing, columnsuffix=Dict(), debug=false)
    table |> MySQL.load(conn, name; append=true, quoteidentifiers=true, limit=typemax(Int64), createtableclause=nothing, columnsuffix=Dict(), debug=false)

Attempts to take a Tables.jl source `table` and load into the database represented by `conn` with table name `name`.

It first detects the `Tables.Schema` of the table source and generates a `CREATE TABLE` statement
with the appropriate column names and types. If no table name is provided, one will be autogenerated, like `odbcjl_xxxxx`.
The `CREATE TABLE` clause can be provided manually by passing the `createtableclause` keyword argument, which
would allow specifying a temporary table or `if not exists`.
Column definitions can also be enhanced by providing arguments to `columnsuffix` as a `Dict` of 
column name (given as a `Symbol`) to a string of the enhancement that will come after name and type like
`[column name] [column type] enhancements`. This allows, for example, specifying the charset of a string column
by doing something like `columnsuffix=Dict(:Name => "CHARACTER SET utf8mb4")`.

Do note that databases vary wildly in requirements for `CREATE TABLE` and column definitions
so it can be extremely difficult to load data generically. You may just need to tweak some of the provided
keyword arguments, but you may also need to execute the `CREATE TABLE` and `INSERT` statements
yourself. If you run into issues, you can [open an issue](https://github.com/JuliaDatabases/MySQL.jl/issues) and
we can see if there's something we can do to make it easier to use this function.
"""
function load end

load(conn::Connection, table::AbstractString="mysql_"*Random.randstring(5); kw...) = x->load(x, conn, table; kw...)

function load(itr, conn::Connection, name::AbstractString="mysql_"*Random.randstring(5); append::Bool=true, quoteidentifiers::Bool=true, debug::Bool=false, limit::Integer=typemax(Int64), kw...)
    # get data
    rows = Tables.rows(itr)
    sch = Tables.schema(rows)
    if sch === nothing
        # we want to ensure we always have a schema, so materialize if needed
        rows = Tables.rows(columntable(rows))
        sch = Tables.schema(rows)
    end
    # ensure table exists
    if quoteidentifiers
        name = quoteid(name)
    end
    try
        createtable(conn, name, sch; quoteidentifiers=quoteidentifiers, debug=debug, kw...)
    catch e
        @warn "error creating table" (e, catch_backtrace())
    end
    if !append
        DBInterface.execute(conn, "DELETE FROM $name")
    end
    # start a transaction for inserting rows
    transaction(conn) do
        params = chop(repeat("?,", length(sch.names)))
        stmt = DBInterface.prepare(conn, "INSERT INTO $name VALUES ($params)")
        for (i, row) in enumerate(rows)
            i > limit && break
            debug && @info "inserting row $i; $(Tables.Row(row))"
            DBInterface.execute(stmt, Tables.Row(row))
        end
    end

    return name
end

function transaction(f::Function, conn)
    API.autocommit(conn.mysql, false)
    try
        f()
        API.commit(conn.mysql)
    catch
        API.rollback(conn.mysql)
        rethrow()
    finally
        API.autocommit(conn.mysql, true)
    end
end