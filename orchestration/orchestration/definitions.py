import os

from dagster import Definitions

from orchestration.assets import all_assets
from orchestration.jobs import all_jobs
from orchestration.resources import RESOURCES
from orchestration.schedule import all_schedules
from orchestration.sensors import all_sensors

deployment_name = os.getenv("DAGSTER_DEPLOYMENT", "local")

defs = Definitions(
    assets=all_assets,
    jobs=all_jobs,
    schedules=all_schedules,
    sensors=all_sensors,
    resources=RESOURCES[deployment_name],
)
