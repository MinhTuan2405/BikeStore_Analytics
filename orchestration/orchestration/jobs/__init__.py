import dagster as dg

supabase_sales_ingestion_job = dg.define_asset_job(
    name="supabase_sales_ingestion_job",
    selection=dg.AssetSelection.assets("raw/supabase/sales"),
)

supabase_production_ingestion_job = dg.define_asset_job(
    name="supabase_production_ingestion_job",
    selection=dg.AssetSelection.assets("raw/supabase/production"),
)

dummyjson_ingestion_job = dg.define_asset_job(
    name="dummyjson_ingestion_job",
    selection=dg.AssetSelection.groups("dummyjson_ingestion"),
)

all_jobs = [supabase_sales_ingestion_job, supabase_production_ingestion_job, dummyjson_ingestion_job]
