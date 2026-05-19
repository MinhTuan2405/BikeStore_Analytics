from dagster import load_assets_from_package_module

from orchestration.assets import dbt, supabase

dbt_assets = load_assets_from_package_module(dbt)
supabase_assets = load_assets_from_package_module(supabase)

all_assets = [*dbt_assets, *supabase_assets]
