from dagster import load_assets_from_package_module

from orchestration.assets import dbt, dummyjson, supabase

dbt_assets = load_assets_from_package_module(dbt)
supabase_assets = load_assets_from_package_module(supabase)
dummyjson_assets = load_assets_from_package_module(dummyjson)

all_assets = [*dbt_assets, *supabase_assets, *dummyjson_assets]
