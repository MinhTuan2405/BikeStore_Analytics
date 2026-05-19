from typing import Any

import dagster as dg
import pandas as pd
import psycopg


class SupabaseResource(dg.ConfigurableResource):
    host: str
    port: int
    database: str
    user: str
    password: str
    sslmode: str

    def _connect(self) -> psycopg.Connection[Any]:
        return psycopg.connect(
            host=self.host,
            port=self.port,
            dbname=self.database,
            user=self.user,
            password=self.password,
            sslmode=self.sslmode,
            connect_timeout=30,
        )

    def fetch_all(self, schema: str, table: str) -> pd.DataFrame:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(f'SELECT * FROM "{schema}"."{table}"')
                cols = [desc[0] for desc in cur.description]
                rows = cur.fetchall()
        return pd.DataFrame(rows, columns=cols)

    def list_tables(self, schema: str) -> list[str]:
        with self._connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT table_name
                    FROM information_schema.tables
                    WHERE table_schema = %s AND table_type = 'BASE TABLE'
                    ORDER BY table_name
                    """,
                    (schema,),
                )
                return [row[0] for row in cur.fetchall()]
