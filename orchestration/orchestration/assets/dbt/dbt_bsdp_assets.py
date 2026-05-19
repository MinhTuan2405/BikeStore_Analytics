from typing import Any, Mapping

import dagster as dg
from dagster_dbt import DagsterDbtTranslator, DbtCliResource, dbt_assets

from orchestration.resources.dbt_resource import dbt_project


class _Translator(DagsterDbtTranslator):
    def get_group_name(self, dbt_resource_props: Mapping[str, Any]) -> str:
        return "BikeStore_Analytics"


@dbt_assets(manifest=dbt_project.manifest_path, dagster_dbt_translator=_Translator())
def dbt_bsdp_assets(context: dg.AssetExecutionContext, dbt: DbtCliResource):
    yield from dbt.cli(["build"], context=context).stream()
