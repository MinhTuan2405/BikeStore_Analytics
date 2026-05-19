# Job / Schedule / Sensor Mapping — Common Patterns

How groups, jobs, schedules, and sensors compose. Pick the pattern that fits the cadence.

## Pattern A — Simple daily cron

```python
# assets/paypal/paypal_data.py
@asset(group_name="paypal_daily_ingestion", partitions_def=DailyPartitionsDefinition(start_date="2026-02-01"))
def paypal_data(context): ...
```

```python
# jobs/__init__.py
paypal_daily_job = define_asset_job(
    name="paypal_daily_job",
    tags={"dagster/max_runtime": 180},
    selection=AssetSelection.groups("paypal_daily_ingestion"),
)
```

```python
# schedule/__init__.py
paypal_daily_schedule = build_schedule_from_partitioned_job(
    job=paypal_daily_job,
    hour_of_day=5,
    minute_of_hour=0,
)
```

Result: every day at 05:00, materialize yesterday's partition for every asset in the group.

Use for: most daily API ingestion pipelines.

## Pattern B — Monthly cron

Same as Pattern A but with `MonthlyPartitionsDefinition` and `build_schedule_from_partitioned_job`. The schedule fires once per month.

Use for: low-frequency exports, billing data, historical refreshes.

## Pattern C — Multi-partition with custom schedule

When a job has more than one partition dimension (e.g. date × brand):

```python
@asset(
    group_name="impact_radius_click_daily_ingestion",
    partitions_def=MultiPartitionsDefinition({
        "date": DailyPartitionsDefinition(start_date="2026-01-01"),
        "brand": StaticPartitionsDefinition(["SCUF", "ELGATO", "CORSAIR"]),
    }),
)
def impact_radius_click(context): ...

impact_radius_click_daily_job = define_asset_job(
    name="impact_radius_click_daily_job",
    selection=AssetSelection.groups("impact_radius_click_daily_ingestion"),
)

@schedule(cron_schedule="0 5 * * *", job=impact_radius_click_daily_job)
def impact_radius_click_daily_schedule():
    partition_date = (datetime.now(timezone.utc) - timedelta(days=2)).strftime("%Y-%m-%d")
    for brand in ["SCUF", "ELGATO", "CORSAIR", "AMAZON_PROGRAM"]:
        yield RunRequest(
            run_key=brand,
            partition_key=MultiPartitionKey({"date": partition_date, "brand": brand}),
        )
```

`build_schedule_from_partitioned_job` doesn't handle multi-dimensional iteration; the `@schedule` decorator + explicit `RunRequest` does.

Use for: per-brand / per-region / per-account fan-out at a fixed cadence.

## Pattern D — Backfill job + sensor

Backfills usually want a longer runtime tag and explicit triggering rather than cron:

```python
zendesk_backfill_job = define_asset_job(
    name="zendesk_backfill_job",
    tags={"dagster/max_runtime": 3600},
    selection=AssetSelection.groups("zendesk_backfill_ingestion"),
)
```

A sensor watches for the trigger condition (a flag in S3, a manual signal, a completed daily run):

```python
@sensor(job=zendesk_backfill_job)
def zendesk_backfill_sensor(context):
    if some_condition():
        yield RunRequest(run_key=..., partition_key=...)
```

Use for: one-off historical loads, replays, gap-filling.

## Pattern E — Run-status reactive sensor (cross-job orchestration)

A sensor fires when another job changes state — used for downstream dbt triggers, alerting, cleanup:

```python
@run_status_sensor(
    run_status=DagsterRunStatus.SUCCESS,
    monitored_jobs=[paypal_daily_job, klarna_daily_job, ...],
    request_job=downstream_dbt_job,
)
def trigger_dbt_after_ingestion(context):
    return RunRequest(run_key=context.dagster_run.run_id)
```

Or for failure alerting:

```python
@run_status_sensor(run_status=DagsterRunStatus.FAILURE, ...)
def alert_on_failure(context):
    send_alert(context.dagster_run)
    return SkipReason("alert sent")
```

Use for: trigger dbt after ingestion, send Slack alert on failure, kick off cleanup on success.

## Pattern F — System / housekeeping jobs

Maintenance jobs that aren't tied to a data source:

```python
docker_system_prune_job = define_asset_job(
    name="docker_system_prune_job",
    selection=AssetSelection.groups("system_maintenance"),
)

docker_system_prune_daily_schedule = build_schedule_from_partitioned_job(
    job=docker_system_prune_job,
    hour_of_day=2,
    minute_of_hour=0,
)
```

Live in `assets/system/`. Same patterns, but the "source" is the platform itself.

Use for: log truncation, metadata cleanup, system health checks.

## Composition rules

- **One group per cadence.** `paypal_daily_ingestion`, not `paypal_ingestion` shared between daily and monthly. The cadence is part of the contract.
- **Jobs use group selection** by default. Drop to `AssetSelection.keys(...)` only when groups aren't precise enough.
- **Schedules mirror jobs** in naming: `paypal_daily_job` → `paypal_daily_schedule`.
- **Sensors mirror their reason**: `_run_failure_sensor`, `_backfill_sensor`, `_post_ingestion_dbt_trigger`.
- **Max runtime tags** on jobs that should die rather than hang: `tags={"dagster/max_runtime": 180}` for 3-minute timeout.
- Long-running backfills get bigger tags (`3600` = 1 hour). Heartbeat / canary jobs get small ones.

## Anti-patterns

- One job listing every asset by key — that's a maintenance nightmare. Use groups.
- Multiple schedules pointing at the same job — one job, one schedule (or one sensor); composition lives in the asset selection.
- Cron logic copy-pasted across schedules — extract a helper in `utils/`.
- Sensors that poll external systems with no rate limit — set `minimum_interval_seconds` and respect the polled system.
- Run-status sensors that fan out to dozens of downstream jobs — split into focused sensors, one per downstream concern.
