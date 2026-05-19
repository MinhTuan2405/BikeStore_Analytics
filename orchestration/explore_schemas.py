import os
from dotenv import load_dotenv
load_dotenv(".env")
import psycopg

conn = psycopg.connect(
    host=os.environ["DATASOURCE_HOST"],
    port=int(os.environ.get("DATASOURCE_PORT", 5432)),
    dbname=os.environ["DATASOURCE_DATABASE"],
    user=os.environ["DATASOURCE_USER"],
    password=os.environ["DATASOURCE_PASSWORD"],
    sslmode=os.environ.get("DATASOURCE_SSLMODE", "require"),
    connect_timeout=15,
)
with conn.cursor() as cur:
    cur.execute("""
        SELECT table_schema, table_name
        FROM information_schema.tables
        WHERE table_type = 'BASE TABLE'
          AND table_schema NOT IN ('pg_catalog','information_schema')
        ORDER BY table_schema, table_name
    """)
    for row in cur.fetchall():
        print(row[0], row[1])
conn.close()
