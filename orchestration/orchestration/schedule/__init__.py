import dagster as dg

from orchestration.jobs import (
    dummyjson_ingestion_job,
    supabase_production_ingestion_job,
    supabase_sales_ingestion_job,
)

supabase_sales_ingestion_schedule = dg.ScheduleDefinition(
    job=supabase_sales_ingestion_job,
    cron_schedule="0 2 * * *",
    default_status=dg.DefaultScheduleStatus.RUNNING,
    description="Daily full-load ingestion of Supabase sales schema at 2 AM UTC.",
)

supabase_production_ingestion_schedule = dg.ScheduleDefinition(
    job=supabase_production_ingestion_job,
    cron_schedule="0 2 * * *",
    default_status=dg.DefaultScheduleStatus.RUNNING,
    description="Daily full-load ingestion of Supabase production schema at 2 AM UTC.",
)

dummyjson_ingestion_schedule = dg.ScheduleDefinition(
    job=dummyjson_ingestion_job,
    cron_schedule="0 2 * * *",
    default_status=dg.DefaultScheduleStatus.RUNNING,
    description="Daily full-load ingestion of dummyjson users API at 2 AM UTC.",
)

all_schedules = [
    supabase_sales_ingestion_schedule,
    supabase_production_ingestion_schedule,
    dummyjson_ingestion_schedule,
]
