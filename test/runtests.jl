using Test, MySQL, DBInterface, Tables, Dates, DecFP

conn = DBInterface.connect(MySQL.Connection, "127.0.0.1", "root", ""; port=3306)
DBInterface.close!(conn)

# load host/user + options from file
conn = DBInterface.connect(MySQL.Connection, "", "", ""; option_file="my.ini")

DBInterface.execute!(conn, "DROP DATABASE if exists mysqltest")
DBInterface.execute!(conn, "CREATE DATABASE mysqltest")
DBInterface.execute!(conn, "use mysqltest")
DBInterface.execute!(conn, """CREATE TABLE Employee
                 (
                     ID INT NOT NULL AUTO_INCREMENT,
                     OfficeNo TINYINT,
                     DeptNo SMALLINT,
                     EmpNo BIGINT UNSIGNED,
                     Wage FLOAT(7,2),
                     Salary DOUBLE,
                     Rate DECIMAL(5, 3),
                     LunchTime TIME,
                     JoinDate DATE,
                     LastLogin DATETIME,
                     LastLogin2 TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                     Initial CHAR(1),
                     Name VARCHAR(255),
                     Photo BLOB,
                     JobType ENUM('HR', 'Management', 'Accounts'),
                     Senior BIT(1),
                     PRIMARY KEY (ID)
                 );""")

DBInterface.execute!(conn, """INSERT INTO Employee (OfficeNo, DeptNo, EmpNo, Wage, Salary, Rate, LunchTime, JoinDate, LastLogin, LastLogin2, Initial, Name, Photo, JobType, Senior)
                 VALUES
                 (1, 2, 1301, 3.14, 10000.50, 1.001, '12:00:00', '2015-8-3', '2015-9-5 12:31:30', '2015-9-5 12:31:30', 'A', 'John', 'abc', 'HR', b'1'),
                 (1, 2, 1422, 3.14, 20000.25, 2.002, '13:00:00', '2015-8-4', '2015-10-12 13:12:14', '2015-10-12 13:12:14', 'B', 'Tom', 'def', 'HR', b'1'),
                 (1, 2, 1567, 3.14, 30000.00, 3.003, '12:30:00', '2015-6-2', '2015-9-5 10:05:10', '2015-9-5 10:05:10', 'C', 'Jim', 'ghi', 'Management', b'0'),
                 (1, 2, 3200, 3.14, 15000.50, 2.5, '12:30:00', '2015-7-25', '2015-10-10 12:12:25', '2015-10-10 12:12:25', 'D', 'Tim', 'jkl', 'Accounts', b'1');
              """)

expected = (
  ID         = Int32[1, 2, 3, 4],
  OfficeNo   = Union{Missing, Int8}[1, 1, 1, 1],
  DeptNo     = Union{Missing, Int16}[2, 2, 2, 2],
  EmpNo      = Union{Missing, UInt64}[1301, 1422, 1567, 3200],
  Wage       = Union{Missing, Float32}[3.14, 3.14, 3.14, 3.14],
  Salary     = Union{Missing, Float64}[10000.5, 20000.25, 30000.0, 15000.5],
  Rate       = Union{Missing, Dec64}[d64"1.001", d64"2.002", d64"3.003", d64"2.5"],
  LunchTime  = Union{Missing, Dates.Time}[Dates.Time(12,00,00), Dates.Time(13,00,00), Dates.Time(12,30,00), Dates.Time(12,30,00)],
  JoinDate   = Union{Missing, Dates.Date}[Date("2015-08-03"), Date("2015-08-04"), Date("2015-06-02"), Date("2015-07-25")],
  LastLogin  = Union{Missing, Dates.DateTime}[DateTime("2015-09-05T12:31:30"), DateTime("2015-10-12T13:12:14"), DateTime("2015-09-05T10:05:10"), DateTime("2015-10-10T12:12:25")],
  LastLogin2 = Dates.DateTime[DateTime("2015-09-05T12:31:30"), DateTime("2015-10-12T13:12:14"), DateTime("2015-09-05T10:05:10"), DateTime("2015-10-10T12:12:25")],
  Initial    = Union{Missing, String}["A", "B", "C", "D"],
  Name       = Union{Missing, String}["John", "Tom", "Jim", "Tim"],
  Photo      = Union{Missing, Vector{UInt8}}[b"abc", b"def", b"ghi", b"jkl"],
  JobType    = Union{Missing, String}["HR", "HR", "Management", "Accounts"],
  Senior     = Union{Missing, MySQL.API.Bit}[MySQL.API.Bit(1), MySQL.API.Bit(1), MySQL.API.Bit(0), MySQL.API.Bit(1)],
)

cursor = DBInterface.execute!(conn, "select * from Employee")
@test DBInterface.lastrowid(cursor) == 1
@test eltype(cursor) == MySQL.TextRow
@test Tables.istable(cursor)
@test Tables.rowaccess(cursor)
@test Tables.rows(cursor) === cursor
@test Tables.schema(cursor) == Tables.Schema(propertynames(expected), eltype.(collect(expected)))
@test Base.IteratorSize(typeof(cursor)) == Base.HasLength()
@test length(cursor) == 4

row = first(cursor)
@test Base.IndexStyle(typeof(row)) == Base.IndexLinear()
@test length(row) == length(expected)
@test propertynames(row) == collect(propertynames(expected))
for (i, prop) in enumerate(propertynames(row))
    @test getproperty(row, prop) == row[prop] == row[i] == expected[prop][1]
end

res = DBInterface.execute!(conn, "select * from Employee") |> columntable
@test length(res) == 16
@test length(res[1]) == 4
@test res == expected

# as a prepared statement
stmt = DBInterface.prepare(conn, "select * from Employee")
cursor = DBInterface.execute!(stmt)
@test DBInterface.lastrowid(cursor) == 1
@test eltype(cursor) == MySQL.Row
@test Tables.istable(cursor)
@test Tables.rowaccess(cursor)
@test Tables.rows(cursor) === cursor
@test Tables.schema(cursor) == Tables.Schema(propertynames(expected), eltype.(collect(expected)))
@test Base.IteratorSize(typeof(cursor)) == Base.HasLength()
@test length(cursor) == 4

row = first(cursor)
@test Base.IndexStyle(typeof(row)) == Base.IndexLinear()
@test length(row) == length(expected)
@test propertynames(row) == collect(propertynames(expected))
for (i, prop) in enumerate(propertynames(row))
    @test getproperty(row, prop) == row[prop] == row[i] == expected[prop][1]
end

res = DBInterface.execute!(stmt) |> columntable
@test length(res) == 16
@test length(res[1]) == 4
@test res == expected

@test DBInterface.close!(stmt) === nothing

# insert null row
DBInterface.execute!(conn, "INSERT INTO Employee () VALUES ();")
for i = 1:length(expected)
    if i == 1
        push!(expected[i], 5)
    elseif i == 11
    else
        push!(expected[i], missing)
    end
end

res = DBInterface.execute!(conn, "select * from Employee") |> columntable
@test length(res) == 16
@test length(res[1]) == 5
for i = 1:length(expected)
    if i != 11
        @test isequal(res[i], expected[i])
    end
end

stmt = DBInterface.prepare(conn, "select * from Employee")
res = DBInterface.execute!(stmt) |> columntable
DBInterface.close!(stmt)
@test length(res) == 16
@test length(res[1]) == 5
for i = 1:length(expected)
    if i != 11
        @test isequal(res[i], expected[i])
    end
end

# now test insert/parameter binding
DBInterface.execute!(conn, "DELETE FROM Employee")
for i = 1:length(expected)
    if i != 11
        pop!(expected[i])
    end
end

stmt = DBInterface.prepare(conn,
    "INSERT INTO Employee (OfficeNo, DeptNo, EmpNo, Wage, Salary, Rate, LunchTime, JoinDate, LastLogin, LastLogin2, Initial, Name, Photo, JobType, Senior)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")

DBInterface.executemany!(stmt, Base.structdiff(expected, NamedTuple{(:ID,)})...)

stmt2 = DBInterface.prepare(conn, "select * from Employee")
res = DBInterface.execute!(stmt2) |> columntable
DBInterface.close!(stmt2)
@test length(res) == 16
@test length(res[1]) == 4
for i = 1:length(expected)
    if i != 11 && i != 1
        @test isequal(res[i], expected[i])
    end
end

DBInterface.execute!(stmt, missing, missing, missing, missing, missing, missing, missing, missing, missing, DateTime("2015-09-05T12:31:30"), missing, missing, missing, missing, missing)
DBInterface.close!(stmt)

stmt = DBInterface.prepare(conn, "select * from Employee")
res = DBInterface.execute!(stmt) |> columntable
DBInterface.close!(stmt)
for i = 1:length(expected)
    if i != 11 && i != 1
        @test res[i][end] === missing
    end
end

# mysql_use_result
res = DBInterface.execute!(conn, "select DeptNo, OfficeNo from Employee"; mysql_store_result=false) |> columntable
@test length(res) == 2
@test length(res[1]) == 5
@test isequal(res.OfficeNo, [1, 1, 1, 1, missing])

stmt = DBInterface.prepare(conn, "select DeptNo, OfficeNo from Employee")
res = DBInterface.execute!(stmt; mysql_store_result=false) |> columntable
DBInterface.close!(stmt)
@test length(res) == 2
@test length(res[1]) == 5
@test isequal(res.OfficeNo, [1, 1, 1, 1, missing])

stmt = DBInterface.prepare(conn, "select DeptNo, OfficeNo from Employee where OfficeNo = ?")
res = DBInterface.execute!(stmt, 1; mysql_store_result=false) |> columntable
DBInterface.close!(stmt)
@test length(res) == 2
@test length(res[1]) == 4
@test isequal(res.OfficeNo, [1, 1, 1, 1])