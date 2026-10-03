import pyodbc

odbc_str = "DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost,1433;DATABASE=TravelWiseDB;UID=sa;PWD=12345;TrustServerCertificate=yes;"
conn = pyodbc.connect(odbc_str)
cursor = conn.cursor()

cursor.execute("SELECT SERVERPROPERTY('Collation')")
print("Server collation:", cursor.fetchone()[0])

cursor.execute("SELECT collation_name FROM sys.databases WHERE name = DB_NAME()")
print("DB collation:", cursor.fetchone()[0])

cursor.execute("SELECT column_name, data_type, collation_name FROM information_schema.columns WHERE table_name='places' AND column_name='name'")
print("Column:", cursor.fetchone())

# Test inserting N-prefixed Unicode string directly
cursor.execute("SELECT id, name FROM places WHERE id = 19")
row = cursor.fetchone()
print("Name repr:", repr(row[1]))
print("Name bytes (UTF-16 hex):", row[1].encode("utf-16-le").hex())

conn.close()
