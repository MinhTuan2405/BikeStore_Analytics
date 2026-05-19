import os

from orchestration.resources.dbt_resource import dbt_resource
from orchestration.resources.dummyjson_resource import DummyjsonResource
from orchestration.resources.supabase_resource import SupabaseResource


def _supabase_resource() -> SupabaseResource:
    return SupabaseResource(
        host=os.environ["DATASOURCE_HOST"],
        port=int(os.environ.get("DATASOURCE_PORT", "5432")),
        database=os.environ["DATASOURCE_DATABASE"],
        user=os.environ["DATASOURCE_USER"],
        password=os.environ["DATASOURCE_PASSWORD"],
        sslmode=os.environ.get("DATASOURCE_SSLMODE", "require"),
    )


def _dummyjson_resource() -> DummyjsonResource:
    return DummyjsonResource(
        base_url=os.environ.get("DUMMYJSON_BASE_URL", "https://dummyjson.com"),
    )


RESOURCES: dict[str, dict] = {
    "local": {
        "dbt": dbt_resource,
        "supabase": _supabase_resource(),
        "dummyjson": _dummyjson_resource(),
    },
    "cloud": {
        "dbt": dbt_resource,
        "supabase": _supabase_resource(),
        "dummyjson": _dummyjson_resource(),
    },
}
