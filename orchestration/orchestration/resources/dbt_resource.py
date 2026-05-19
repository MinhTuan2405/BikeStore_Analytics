from pathlib import Path

from dagster_dbt import DbtCliResource, DbtProject

DBT_PROJECT_DIR = Path(__file__).parents[3] / "dbt_bsdp"

dbt_project = DbtProject(project_dir=DBT_PROJECT_DIR)
dbt_project.prepare_if_dev()

dbt_resource = DbtCliResource(project_dir=dbt_project)
