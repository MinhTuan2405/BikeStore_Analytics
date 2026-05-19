import os
from pathlib import Path

from dagster_dbt import DbtCliResource, DbtProject

DBT_PROJECT_DIR = Path(
    os.getenv("DBT_PROJECT_DIR", Path(__file__).resolve().parents[3] / "dbt_bsdp")
).resolve()

dbt_project = DbtProject(project_dir=DBT_PROJECT_DIR, profiles_dir=DBT_PROJECT_DIR)
dbt_project.prepare_if_dev()

if not dbt_project.manifest_path.exists():
    DbtCliResource(project_dir=dbt_project).cli(
        ["parse", "--quiet"],
        target_path=dbt_project.target_path,
    ).wait()

dbt_resource = DbtCliResource(project_dir=dbt_project)
