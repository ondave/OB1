from pydantic_settings import BaseSettings
from typing import List


class Settings(BaseSettings):
    """Application settings"""

    PROJECT_NAME: str = "{{APP_NAME}}"
    PROJECT_DESCRIPTION: str = "{{APP_DESCRIPTION}}"
    VERSION: str = "0.1.0"

    # CORS
    CORS_ORIGINS: List[str] = ["http://localhost:3000", "http://localhost:5173"]

    # API Settings
    API_V1_PREFIX: str = "/api/v1"

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
