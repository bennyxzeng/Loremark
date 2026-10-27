"""Responses API adapter (OpenAI, or DeepSeek's compatible endpoint) with failure capture.

The output model is a parameter: ChapterStoryModel for `generate` (the default), StoryDelta
for cumulative updates. `responses.parse` raises when the output does not fit the schema,
which would lose the response. Calling it through `with_raw_response` keeps the HTTP body
available, so status, refusals, usage, and the raw output text are saved before parsing is
attempted.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, Literal, Protocol

import openai
import pydantic

from .config import GenerateConfig
from .schemas import ChapterStoryModel

OutputModel = type[pydantic.BaseModel]

if TYPE_CHECKING:
    import httpx2

CallStatus = Literal[
    "completed", "refusal", "incomplete", "failed", "empty_output", "api_error", "parse_error"
]

_STATUS_CATEGORIES = {
    400: "invalid_request",
    401: "authentication",
    403: "permission_denied",
    404: "not_found",
    409: "conflict",
    422: "unprocessable",
    429: "rate_limit",
}


@dataclass
class CallResult:
    status: CallStatus
    parsed: pydantic.BaseModel | None = None
    candidate: Any = None
    output_text: str | None = None
    response_body: Any = None
    request_id: str | None = None
    response_id: str | None = None
    response_model: str | None = None
    usage: dict[str, Any] | None = None
    error: dict[str, Any] | None = None
    elapsed_seconds: float | None = None
    retries_taken: int | None = None


class StoryModelClient(Protocol):
    def generate(
        self, params: dict[str, Any], output_type: OutputModel = ChapterStoryModel
    ) -> CallResult: ...


def make_sdk_client(
    config: GenerateConfig, api_key: str, http_client: httpx2.Client | None = None
) -> openai.OpenAI:
    client = openai.OpenAI(
        api_key=api_key,
        base_url=config.base_url,
        timeout=config.timeout,
        max_retries=config.max_retries,
        http_client=http_client,
    )
    if config.provider.name != "openai":
        # The SDK fills these from OPENAI_ORG_ID / OPENAI_PROJECT_ID; never forward them
        # to a third-party endpoint.
        client.organization = None
        client.project = None
    return client


class ResponsesClient:
    def __init__(self, sdk: openai.OpenAI) -> None:
        self._sdk = sdk

    def generate(
        self, params: dict[str, Any], output_type: OutputModel = ChapterStoryModel
    ) -> CallResult:
        started = time.monotonic()
        try:
            raw = self._sdk.responses.with_raw_response.parse(text_format=output_type, **params)
        except openai.APIStatusError as exc:
            result = CallResult(status="api_error", request_id=exc.request_id)
            result.error = {
                "category": _status_category(exc.status_code),
                "type": type(exc).__name__,
                "status_code": exc.status_code,
                "message": str(exc),
                "body": exc.body,
            }
        except openai.APITimeoutError as exc:
            result = CallResult(status="api_error", error=_error("timeout", exc))
        except openai.APIConnectionError as exc:
            result = CallResult(status="api_error", error=_error("network", exc))
        except openai.OpenAIError as exc:
            result = CallResult(status="api_error", error=_error("sdk_error", exc))
        else:
            result = _interpret(raw)
        result.elapsed_seconds = round(time.monotonic() - started, 3)
        return result


def _status_category(status_code: int) -> str:
    if status_code >= 500:
        return "server_error"
    return _STATUS_CATEGORIES.get(status_code, "http_error")


def _error(category: str, exc: BaseException, **extra: Any) -> dict[str, Any]:
    return {"category": category, "type": type(exc).__name__, "message": str(exc), **extra}


def _interpret(raw: Any) -> CallResult:
    result = CallResult(
        status="completed", request_id=raw.request_id, retries_taken=raw.retries_taken
    )
    try:
        body = raw.http_response.json()
    except ValueError as exc:
        result.status = "api_error"
        result.error = _error("invalid_response_body", exc, body_text=raw.http_response.text)
        return result
    if not isinstance(body, dict):
        result.status = "api_error"
        result.error = {"category": "invalid_response_body", "message": "Body is not an object"}
        return result

    result.response_body = body
    result.response_id = body.get("id")
    result.response_model = body.get("model")
    result.usage = body.get("usage")
    status = body.get("status")
    texts, refusals = _final_message_parts(body)
    result.output_text = texts[0] if texts else None

    if body.get("error") or status == "failed":
        result.status = "failed"
        result.error = {
            "category": "response_failed",
            "status": status,
            "detail": body.get("error"),
        }
    elif refusals:
        result.status = "refusal"
        result.error = {"category": "refusal", "message": "\n".join(refusals)}
    elif status == "incomplete":
        result.status = "incomplete"
        result.error = {"category": "incomplete", "detail": body.get("incomplete_details")}
    elif status not in ("completed", None):
        result.status = "failed"
        result.error = {"category": "unexpected_status", "status": status}
    elif not texts:
        result.status = "empty_output"
        result.error = {"category": "empty_output", "message": "No output_text in the response"}
    else:
        _parse(raw, result)
    return result


def _final_message_parts(body: dict[str, Any]) -> tuple[list[str], list[str]]:
    """Output texts and refusals of final-answer messages, in order."""
    texts: list[str] = []
    refusals: list[str] = []
    for item in body.get("output") or []:
        if item.get("type") != "message" or item.get("phase") not in (None, "final_answer"):
            continue
        for part in item.get("content") or []:
            if part.get("type") == "output_text":
                texts.append(part.get("text") or "")
            elif part.get("type") == "refusal":
                refusals.append(part.get("refusal") or "")
    return texts, refusals


def _parse(raw: Any, result: CallResult) -> None:
    try:
        result.candidate = json.loads(result.output_text or "")
    except json.JSONDecodeError as exc:
        result.status = "parse_error"
        result.error = _error("invalid_json", exc)
        return
    try:
        parsed = raw.parse().output_parsed
    except pydantic.ValidationError as exc:
        result.status = "parse_error"
        result.error = _error(
            "schema_mismatch", exc, errors=json.loads(exc.json(include_url=False))
        )
        return
    except (ValueError, TypeError) as exc:
        result.status = "parse_error"
        result.error = _error("sdk_parse_error", exc)
        return
    if parsed is None:
        result.status = "empty_output"
        result.error = {"category": "empty_output", "message": "SDK returned no parsed output"}
        return
    result.parsed = parsed
