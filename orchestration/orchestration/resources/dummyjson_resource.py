import dagster as dg
import pandas as pd
import requests


class DummyjsonResource(dg.ConfigurableResource):
    base_url: str
    page_size: int = 100

    def _fetch_paginated(self, endpoint: str, collection_key: str) -> list[dict]:
        items: list[dict] = []
        skip = 0
        total: int | None = None

        while total is None or skip < total:
            response = requests.get(
                f"{self.base_url}/{endpoint}",
                params={"skip": skip, "limit": self.page_size},
                timeout=30,
            )
            response.raise_for_status()
            data: dict = response.json()

            if total is None:
                total = data["total"]

            batch: list[dict] = data[collection_key]
            if not batch:
                break

            items.extend(batch)
            skip += len(batch)

        return items

    def fetch_users(self) -> pd.DataFrame:
        return pd.json_normalize(self._fetch_paginated("users", "users"), sep="_")

    def fetch_products(self) -> pd.DataFrame:
        return pd.json_normalize(self._fetch_paginated("products", "products"), sep="_")
