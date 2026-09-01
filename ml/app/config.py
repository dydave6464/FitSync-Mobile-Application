"""Settings for the FitSync ML service.

The service refuses to start without database credentials. A generator that
cannot read the catalogue would return 502 on every onboarding, and failing at
boot is louder -- and cheaper to diagnose -- than failing per request.
See the design, section 12.
"""
from dataclasses import dataclass
from typing import Mapping

REQUIRED = (
    "FITSYNC_DB_HOST",
    "FITSYNC_DB_PORT",
    "FITSYNC_DB_USER",
    "FITSYNC_DB_PASSWORD",
    "FITSYNC_DB_NAME",
)


@dataclass(frozen=True)
class Settings:
    db_host: str
    db_port: int
    db_user: str
    db_password: str
    db_name: str
    model_dir: str = "models"
    log_level: str = "info"

    @classmethod
    def from_env(cls, env: Mapping[str, str]) -> "Settings":
        missing = [name for name in REQUIRED if not env.get(name)]
        if missing:
            raise ValueError(
                "missing required environment variables: " + ", ".join(missing)
            )

        raw_port = env["FITSYNC_DB_PORT"]
        try:
            port = int(raw_port)
        except ValueError:
            raise ValueError(
                "FITSYNC_DB_PORT must be an integer, got {!r}".format(raw_port)
            )

        return cls(
            db_host=env["FITSYNC_DB_HOST"],
            db_port=port,
            db_user=env["FITSYNC_DB_USER"],
            db_password=env["FITSYNC_DB_PASSWORD"],
            db_name=env["FITSYNC_DB_NAME"],
            model_dir=env.get("FITSYNC_MODEL_DIR", "models"),
            log_level=env.get("FITSYNC_LOG_LEVEL", "info"),
        )
