"""Provider profiles and generate settings, resolved from CLI flags and environment variables.

Only environment variables are read; no .env or other secret files are loaded.
"""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import dataclass

SDK_MAX_RETRIES = 2


class ConfigError(Exception):
    """Invalid or missing configuration (exit code 2)."""


@dataclass(frozen=True)
class ProviderProfile:
    name: str
    api_key_env: str
    model_env: str
    base_url_env: str
    default_base_url: str
    # DeepSeek silently ignores `store` and `truncation` (it never stores responses and
    # rejects over-long input with HTTP 400), so they are only sent where they take effect.
    sends_store_and_truncation: bool


PROVIDERS: dict[str, ProviderProfile] = {
    "openai": ProviderProfile(
        name="openai",
        api_key_env="OPENAI_API_KEY",
        model_env="OPENAI_MODEL",
        base_url_env="OPENAI_BASE_URL",
        default_base_url="https://api.openai.com/v1",
        sends_store_and_truncation=True,
    ),
    "deepseek": ProviderProfile(
        name="deepseek",
        api_key_env="DEEPSEEK_API_KEY",
        model_env="DEEPSEEK_MODEL",
        base_url_env="DEEPSEEK_BASE_URL",
        default_base_url="https://api.deepseek.com",
        sends_store_and_truncation=False,
    ),
}


@dataclass(frozen=True)
class GenerateConfig:
    provider: ProviderProfile
    model: str | None
    base_url: str
    # None means unset: no max_output_tokens is sent, and requests have no client timeout.
    max_output_tokens: int | None
    timeout: float | None
    dry_run: bool
    # Sent as reasoning.effort only when set; accepted values depend on provider and model.
    reasoning_effort: str | None = None
    max_retries: int = SDK_MAX_RETRIES

    def api_key(self, env: Mapping[str, str] | None = None) -> str:
        """Return the provider API key, failing early when a live call is not configured."""
        env = os.environ if env is None else env
        key = env.get(self.provider.api_key_env, "").strip()
        if not key:
            raise ConfigError(
                f"{self.provider.api_key_env} is not set; export it in your shell "
                f"(provider {self.provider.name!r}), or use --dry-run"
            )
        if not self.model:
            raise ConfigError(
                f"No model configured: pass --model or set {self.provider.model_env}. "
                "The model must support the Responses API with Structured Outputs."
            )
        return key


def resolve_generate_config(
    *,
    provider: str,
    model: str | None,
    max_output_tokens: int | None,
    timeout: float | None,
    dry_run: bool,
    reasoning_effort: str | None = None,
    env: Mapping[str, str] | None = None,
) -> GenerateConfig:
    env = os.environ if env is None else env
    profile = PROVIDERS.get(provider)
    if profile is None:
        raise ConfigError(f"Unknown provider {provider!r}; choose one of {', '.join(PROVIDERS)}")
    if max_output_tokens is not None and max_output_tokens <= 0:
        raise ConfigError("--max-output-tokens must be a positive integer")
    if timeout is not None and timeout <= 0:
        raise ConfigError("--timeout must be positive")
    if reasoning_effort is not None and not reasoning_effort.strip():
        raise ConfigError("--reasoning-effort must not be empty")
    resolved_model = (model or env.get(profile.model_env, "")).strip() or None
    base_url = env.get(profile.base_url_env, "").strip() or profile.default_base_url
    return GenerateConfig(
        provider=profile,
        model=resolved_model,
        base_url=base_url,
        max_output_tokens=max_output_tokens,
        timeout=timeout,
        dry_run=dry_run,
        reasoning_effort=reasoning_effort.strip() if reasoning_effort else None,
    )
