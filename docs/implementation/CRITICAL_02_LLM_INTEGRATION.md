# Critical Issue #2: LLM Integration Layer Deep-Dive

## The Problem

Your agent system defines capabilities but has **no intelligence substrate**:

```yaml
# Current: Capability declaration without implementation
researcher:
  capabilities:
    - literature_review      # HOW does it do this?
    - hypothesis_formation   # WHAT model? WHAT prompt?
```

**Missing:**
- No LLM provider abstraction (Claude, GPT, local models)
- No prompt management system
- No tool invocation framework
- No reasoning trace capture
- No cost/rate limit management

---

## The Solution: LLM Abstraction Layer

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      AGENT LAYER                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Researcher Agent  │  Architect Agent  │  Implementer    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   AGENT RUNTIME                           │  │
│  │    • Prompt Builder    • Tool Executor   • Memory         │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    LLM ABSTRACTION LAYER                         │
│  ┌────────────────────────────────────────────────────────────┐│
│  │                    LLM Gateway                              ││
│  │  • Provider Selection   • Rate Limiting   • Cost Tracking  ││
│  │  • Fallback Logic       • Retry Handling  • Caching        ││
│  └────────────────────────────────────────────────────────────┘│
│                              │                                   │
│      ┌───────────────────────┼───────────────────────┐         │
│      ▼                       ▼                       ▼         │
│  ┌────────┐            ┌────────┐             ┌────────┐       │
│  │ Claude │            │  GPT   │             │ Local  │       │
│  │Provider│            │Provider│             │(Ollama)│       │
│  └────────┘            └────────┘             └────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implementation

### 1. LLM Provider Abstraction

```python
# company_os/core/llm/provider.py

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, AsyncIterator
from enum import Enum
import time


class Role(Enum):
    SYSTEM = "system"
    USER = "user"
    ASSISTANT = "assistant"
    TOOL = "tool"


@dataclass
class Message:
    """A message in the conversation."""
    role: Role
    content: str
    name: Optional[str] = None  # For tool messages
    tool_calls: Optional[List[Dict]] = None
    tool_call_id: Optional[str] = None


@dataclass
class ToolDefinition:
    """Definition of a tool the LLM can call."""
    name: str
    description: str
    parameters: Dict[str, Any]  # JSON Schema


@dataclass
class LLMResponse:
    """Response from an LLM provider."""
    content: str
    tool_calls: Optional[List[Dict]] = None
    finish_reason: str = "stop"
    usage: Dict[str, int] = field(default_factory=dict)
    model: str = ""
    latency_ms: float = 0


@dataclass
class LLMConfig:
    """Configuration for LLM requests."""
    model: str
    temperature: float = 0.7
    max_tokens: int = 4096
    top_p: float = 1.0
    timeout: int = 120
    stream: bool = False


class LLMProvider(ABC):
    """Abstract base class for LLM providers."""

    @abstractmethod
    async def complete(
        self,
        messages: List[Message],
        config: LLMConfig,
        tools: Optional[List[ToolDefinition]] = None
    ) -> LLMResponse:
        """Generate a completion."""
        pass

    @abstractmethod
    async def stream(
        self,
        messages: List[Message],
        config: LLMConfig,
        tools: Optional[List[ToolDefinition]] = None
    ) -> AsyncIterator[str]:
        """Stream a completion."""
        pass

    @abstractmethod
    def count_tokens(self, text: str) -> int:
        """Count tokens in text."""
        pass
```

### 2. Claude Provider Implementation

```python
# company_os/core/llm/providers/anthropic.py

import anthropic
from typing import List, Optional, AsyncIterator
import time

from ..provider import (
    LLMProvider, Message, LLMConfig, LLMResponse,
    ToolDefinition, Role
)


class AnthropicProvider(LLMProvider):
    """Claude/Anthropic LLM provider."""

    MODEL_MAP = {
        "claude-3-opus": "claude-3-opus-20240229",
        "claude-3-sonnet": "claude-3-sonnet-20240229",
        "claude-3-haiku": "claude-3-haiku-20240307",
        "claude-3.5-sonnet": "claude-3-5-sonnet-20241022",
        "claude-opus-4": "claude-opus-4-20250514",
    }

    def __init__(self, api_key: str):
        self.client = anthropic.AsyncAnthropic(api_key=api_key)

    async def complete(
        self,
        messages: List[Message],
        config: LLMConfig,
        tools: Optional[List[ToolDefinition]] = None
    ) -> LLMResponse:
        start_time = time.time()

        # Convert messages to Anthropic format
        system_message = None
        anthropic_messages = []

        for msg in messages:
            if msg.role == Role.SYSTEM:
                system_message = msg.content
            else:
                anthropic_messages.append({
                    "role": msg.role.value,
                    "content": msg.content
                })

        # Convert tools to Anthropic format
        anthropic_tools = None
        if tools:
            anthropic_tools = [
                {
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.parameters
                }
                for tool in tools
            ]

        # Make request
        model = self.MODEL_MAP.get(config.model, config.model)

        response = await self.client.messages.create(
            model=model,
            max_tokens=config.max_tokens,
            temperature=config.temperature,
            system=system_message,
            messages=anthropic_messages,
            tools=anthropic_tools
        )

        # Extract tool calls if present
        tool_calls = None
        content = ""

        for block in response.content:
            if block.type == "text":
                content = block.text
            elif block.type == "tool_use":
                if tool_calls is None:
                    tool_calls = []
                tool_calls.append({
                    "id": block.id,
                    "name": block.name,
                    "arguments": block.input
                })

        return LLMResponse(
            content=content,
            tool_calls=tool_calls,
            finish_reason=response.stop_reason,
            usage={
                "input_tokens": response.usage.input_tokens,
                "output_tokens": response.usage.output_tokens
            },
            model=model,
            latency_ms=(time.time() - start_time) * 1000
        )

    async def stream(
        self,
        messages: List[Message],
        config: LLMConfig,
        tools: Optional[List[ToolDefinition]] = None
    ) -> AsyncIterator[str]:
        # Similar to complete but with streaming
        system_message = None
        anthropic_messages = []

        for msg in messages:
            if msg.role == Role.SYSTEM:
                system_message = msg.content
            else:
                anthropic_messages.append({
                    "role": msg.role.value,
                    "content": msg.content
                })

        model = self.MODEL_MAP.get(config.model, config.model)

        async with self.client.messages.stream(
            model=model,
            max_tokens=config.max_tokens,
            temperature=config.temperature,
            system=system_message,
            messages=anthropic_messages
        ) as stream:
            async for text in stream.text_stream:
                yield text

    def count_tokens(self, text: str) -> int:
        # Approximate: ~4 chars per token for Claude
        return len(text) // 4
```

### 3. OpenAI Provider Implementation

```python
# company_os/core/llm/providers/openai.py

import openai
from typing import List, Optional, AsyncIterator
import time
import json

from ..provider import (
    LLMProvider, Message, LLMConfig, LLMResponse,
    ToolDefinition, Role
)


class OpenAIProvider(LLMProvider):
    """OpenAI GPT provider."""

    MODEL_MAP = {
        "gpt-4": "gpt-4-turbo-preview",
        "gpt-4o": "gpt-4o",
        "gpt-4o-mini": "gpt-4o-mini",
        "gpt-3.5": "gpt-3.5-turbo",
    }

    def __init__(self, api_key: str):
        self.client = openai.AsyncOpenAI(api_key=api_key)

    async def complete(
        self,
        messages: List[Message],
        config: LLMConfig,
        tools: Optional[List[ToolDefinition]] = None
    ) -> LLMResponse:
        start_time = time.time()

        # Convert messages to OpenAI format
        openai_messages = [
            {"role": msg.role.value, "content": msg.content}
            for msg in messages
        ]

        # Convert tools to OpenAI format
        openai_tools = None
        if tools:
            openai_tools = [
                {
                    "type": "function",
                    "function": {
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": tool.parameters
                    }
                }
                for tool in tools
            ]

        model = self.MODEL_MAP.get(config.model, config.model)

        kwargs = {
            "model": model,
            "messages": openai_messages,
            "max_tokens": config.max_tokens,
            "temperature": config.temperature,
        }

        if openai_tools:
            kwargs["tools"] = openai_tools

        response = await self.client.chat.completions.create(**kwargs)

        # Extract response
        choice = response.choices[0]
        content = choice.message.content or ""

        tool_calls = None
        if choice.message.tool_calls:
            tool_calls = [
                {
                    "id": tc.id,
                    "name": tc.function.name,
                    "arguments": json.loads(tc.function.arguments)
                }
                for tc in choice.message.tool_calls
            ]

        return LLMResponse(
            content=content,
            tool_calls=tool_calls,
            finish_reason=choice.finish_reason,
            usage={
                "input_tokens": response.usage.prompt_tokens,
                "output_tokens": response.usage.completion_tokens
            },
            model=model,
            latency_ms=(time.time() - start_time) * 1000
        )

    async def stream(
        self,
        messages: List[Message],
        config: LLMConfig,
        tools: Optional[List[ToolDefinition]] = None
    ) -> AsyncIterator[str]:
        openai_messages = [
            {"role": msg.role.value, "content": msg.content}
            for msg in messages
        ]

        model = self.MODEL_MAP.get(config.model, config.model)

        stream = await self.client.chat.completions.create(
            model=model,
            messages=openai_messages,
            max_tokens=config.max_tokens,
            temperature=config.temperature,
            stream=True
        )

        async for chunk in stream:
            if chunk.choices[0].delta.content:
                yield chunk.choices[0].delta.content

    def count_tokens(self, text: str) -> int:
        # Use tiktoken for accurate count
        try:
            import tiktoken
            enc = tiktoken.encoding_for_model("gpt-4")
            return len(enc.encode(text))
        except:
            return len(text) // 4
```

### 4. LLM Gateway (Provider Router)

```python
# company_os/core/llm/gateway.py

from typing import Dict, List, Optional, AsyncIterator
from dataclasses import dataclass
import asyncio
import logging

from .provider import (
    LLMProvider, Message, LLMConfig, LLMResponse,
    ToolDefinition
)
from .providers.anthropic import AnthropicProvider
from .providers.openai import OpenAIProvider


@dataclass
class ProviderConfig:
    """Configuration for a provider."""
    provider_type: str  # "anthropic", "openai", "local"
    api_key: str
    default_model: str
    rate_limit_rpm: int = 60  # Requests per minute
    fallback_provider: Optional[str] = None
    enabled: bool = True


class LLMGateway:
    """
    Central gateway for all LLM operations.

    Features:
    - Multiple provider support with fallback
    - Rate limiting per provider
    - Cost tracking
    - Request caching
    - Automatic retries
    """

    def __init__(self, configs: Dict[str, ProviderConfig]):
        self.configs = configs
        self.providers: Dict[str, LLMProvider] = {}
        self._rate_limiters: Dict[str, asyncio.Semaphore] = {}
        self._request_counts: Dict[str, int] = {}
        self._cost_tracker: Dict[str, float] = {}

        self._initialize_providers()

    def _initialize_providers(self):
        """Initialize all configured providers."""
        for name, config in self.configs.items():
            if not config.enabled:
                continue

            if config.provider_type == "anthropic":
                self.providers[name] = AnthropicProvider(config.api_key)
            elif config.provider_type == "openai":
                self.providers[name] = OpenAIProvider(config.api_key)
            # Add more providers as needed

            # Initialize rate limiter
            self._rate_limiters[name] = asyncio.Semaphore(
                config.rate_limit_rpm
            )

    async def complete(
        self,
        messages: List[Message],
        provider: str = "default",
        config: Optional[LLMConfig] = None,
        tools: Optional[List[ToolDefinition]] = None,
        retry_count: int = 3
    ) -> LLMResponse:
        """
        Generate a completion with automatic fallback and retry.
        """
        # Resolve provider
        if provider == "default":
            provider = self._get_default_provider()

        if provider not in self.providers:
            raise ValueError(f"Unknown provider: {provider}")

        provider_config = self.configs[provider]
        llm_provider = self.providers[provider]

        # Use default config if not provided
        if config is None:
            config = LLMConfig(model=provider_config.default_model)

        # Rate limiting
        async with self._rate_limiters[provider]:
            for attempt in range(retry_count):
                try:
                    response = await llm_provider.complete(
                        messages=messages,
                        config=config,
                        tools=tools
                    )

                    # Track usage
                    self._track_usage(provider, response)

                    return response

                except Exception as e:
                    logging.warning(
                        f"Provider {provider} failed (attempt {attempt + 1}): {e}"
                    )

                    # Try fallback on last attempt
                    if attempt == retry_count - 1:
                        if provider_config.fallback_provider:
                            return await self.complete(
                                messages=messages,
                                provider=provider_config.fallback_provider,
                                config=config,
                                tools=tools,
                                retry_count=1
                            )
                        raise

                    # Exponential backoff
                    await asyncio.sleep(2 ** attempt)

    async def stream(
        self,
        messages: List[Message],
        provider: str = "default",
        config: Optional[LLMConfig] = None
    ) -> AsyncIterator[str]:
        """Stream a completion."""
        if provider == "default":
            provider = self._get_default_provider()

        provider_config = self.configs[provider]
        llm_provider = self.providers[provider]

        if config is None:
            config = LLMConfig(model=provider_config.default_model)

        async with self._rate_limiters[provider]:
            async for chunk in llm_provider.stream(messages, config):
                yield chunk

    def _get_default_provider(self) -> str:
        """Get the default provider (first enabled one)."""
        for name, config in self.configs.items():
            if config.enabled:
                return name
        raise ValueError("No enabled providers")

    def _track_usage(self, provider: str, response: LLMResponse):
        """Track token usage and costs."""
        self._request_counts[provider] = (
            self._request_counts.get(provider, 0) + 1
        )

        # Calculate cost (approximate)
        cost = self._calculate_cost(
            provider,
            response.model,
            response.usage.get("input_tokens", 0),
            response.usage.get("output_tokens", 0)
        )
        self._cost_tracker[provider] = (
            self._cost_tracker.get(provider, 0) + cost
        )

    def _calculate_cost(
        self,
        provider: str,
        model: str,
        input_tokens: int,
        output_tokens: int
    ) -> float:
        """Calculate cost in USD."""
        # Pricing per 1M tokens (as of 2024)
        pricing = {
            "claude-3-opus": {"input": 15.0, "output": 75.0},
            "claude-3-sonnet": {"input": 3.0, "output": 15.0},
            "claude-3-haiku": {"input": 0.25, "output": 1.25},
            "claude-3.5-sonnet": {"input": 3.0, "output": 15.0},
            "gpt-4-turbo": {"input": 10.0, "output": 30.0},
            "gpt-4o": {"input": 5.0, "output": 15.0},
            "gpt-4o-mini": {"input": 0.15, "output": 0.60},
        }

        # Find matching pricing
        for model_prefix, rates in pricing.items():
            if model_prefix in model:
                return (
                    (input_tokens / 1_000_000) * rates["input"] +
                    (output_tokens / 1_000_000) * rates["output"]
                )

        return 0.0

    def get_stats(self) -> Dict:
        """Get usage statistics."""
        return {
            "request_counts": self._request_counts.copy(),
            "total_cost_usd": sum(self._cost_tracker.values()),
            "cost_by_provider": self._cost_tracker.copy()
        }
```

### 5. Prompt Management System

```python
# company_os/core/llm/prompts.py

from typing import Any, Dict, List, Optional
from dataclasses import dataclass
from pathlib import Path
import yaml
import jinja2


@dataclass
class PromptTemplate:
    """A prompt template with variables."""
    name: str
    version: str
    system: str
    user: Optional[str] = None
    few_shot_examples: List[Dict] = None
    variables: List[str] = None


class PromptManager:
    """
    Manages prompt templates with versioning and variable substitution.

    Prompts are stored as YAML files:
    prompts/
      researcher/
        literature_review.yaml
        hypothesis_formation.yaml
      architect/
        system_design.yaml
    """

    def __init__(self, prompts_dir: str):
        self.prompts_dir = Path(prompts_dir)
        self.templates: Dict[str, PromptTemplate] = {}
        self.jinja_env = jinja2.Environment(
            loader=jinja2.FileSystemLoader(str(self.prompts_dir)),
            undefined=jinja2.StrictUndefined
        )
        self._load_templates()

    def _load_templates(self):
        """Load all prompt templates from disk."""
        for yaml_file in self.prompts_dir.rglob("*.yaml"):
            with open(yaml_file) as f:
                data = yaml.safe_load(f)

            # Construct template name from path
            rel_path = yaml_file.relative_to(self.prompts_dir)
            name = str(rel_path.with_suffix("")).replace("/", ".")

            self.templates[name] = PromptTemplate(
                name=name,
                version=data.get("version", "1.0"),
                system=data.get("system", ""),
                user=data.get("user"),
                few_shot_examples=data.get("few_shot_examples", []),
                variables=data.get("variables", [])
            )

    def get(self, name: str) -> PromptTemplate:
        """Get a prompt template by name."""
        if name not in self.templates:
            raise ValueError(f"Unknown prompt template: {name}")
        return self.templates[name]

    def render(
        self,
        name: str,
        variables: Dict[str, Any]
    ) -> Dict[str, str]:
        """
        Render a prompt template with variables.

        Returns dict with 'system' and optionally 'user' keys.
        """
        template = self.get(name)

        # Check required variables
        for var in template.variables or []:
            if var not in variables:
                raise ValueError(
                    f"Missing required variable '{var}' for prompt '{name}'"
                )

        # Render system prompt
        system = jinja2.Template(template.system).render(**variables)

        result = {"system": system}

        # Render user prompt if present
        if template.user:
            result["user"] = jinja2.Template(template.user).render(**variables)

        # Add few-shot examples if present
        if template.few_shot_examples:
            result["few_shot"] = template.few_shot_examples

        return result

    def list_templates(self) -> List[str]:
        """List all available template names."""
        return list(self.templates.keys())
```

### 6. Example Prompt Templates

```yaml
# prompts/researcher/literature_review.yaml

version: "1.0"

variables:
  - topic
  - context
  - constraints

system: |
  You are a Principal Research Scientist with expertise in systematic literature reviews.

  Your approach:
  1. Start with broad search, then narrow based on relevance
  2. Prioritize peer-reviewed sources over preprints
  3. Note methodology strengths and weaknesses
  4. Identify research gaps and contradictions
  5. Synthesize findings into actionable insights

  Quality standards:
  - Every claim must have a citation
  - Note publication year and impact factor when relevant
  - Flag potential biases in studies
  - Distinguish between correlation and causation

  Current project context:
  {{ context }}

  Constraints:
  {{ constraints }}

user: |
  Please conduct a literature review on: {{ topic }}

  Provide:
  1. Summary of key findings (3-5 bullet points)
  2. Methodology comparison table
  3. Research gaps identified
  4. Recommended next steps

few_shot_examples:
  - input: "Review recent advances in transformer architectures for NLP"
    output: |
      ## Key Findings

      1. **Attention is Not All You Need** (2023): Recent work shows that combining attention with state-space models improves efficiency...

      2. **Scaling Laws** (2022): Performance scales predictably with model size, but with diminishing returns above 100B parameters...

      ## Methodology Comparison

      | Paper | Architecture | Dataset | Key Innovation |
      |-------|--------------|---------|----------------|
      | Mamba (2024) | SSM + Attention | Pile | Linear-time attention |

      ## Research Gaps

      - Limited work on efficient fine-tuning for domain-specific tasks
      - Few studies on multi-modal transformers at scale

      ## Recommended Next Steps

      - Investigate Mamba architecture for our use case
      - Benchmark against standard transformer baseline
```

```yaml
# prompts/implementer/code_generation.yaml

version: "1.0"

variables:
  - task_description
  - existing_code
  - tech_stack
  - coding_standards

system: |
  You are a Senior Software Engineer implementing production-quality code.

  Tech Stack: {{ tech_stack }}

  Coding Standards:
  {{ coding_standards }}

  Requirements:
  1. Write clean, maintainable code
  2. Include appropriate error handling
  3. Add type hints (Python) or types (TypeScript)
  4. Write docstrings/comments for complex logic
  5. Consider edge cases

  Security considerations:
  - Never hardcode secrets
  - Validate all inputs
  - Use parameterized queries for database operations
  - Sanitize outputs to prevent XSS

  Existing code context:
  ```
  {{ existing_code }}
  ```

user: |
  Implement the following:

  {{ task_description }}

  Provide:
  1. Implementation code
  2. Unit tests
  3. Brief explanation of design decisions
```

### 7. Agent Runtime with LLM Integration

```python
# company_os/agents/runtime.py

from typing import Any, Dict, List, Optional
from dataclasses import dataclass, field
from datetime import datetime
import uuid
import json

from company_os.core.llm.gateway import LLMGateway
from company_os.core.llm.prompts import PromptManager
from company_os.core.llm.provider import Message, Role, ToolDefinition, LLMConfig
from company_os.core.events.store import EventStore


@dataclass
class AgentConfig:
    """Configuration for an agent."""
    agent_type: str
    persona_prompt: str
    default_model: str
    available_tools: List[str]
    autonomy_level: str = "supervised"  # manual, supervised, autonomous
    max_iterations: int = 10
    temperature: float = 0.7


@dataclass
class AgentContext:
    """Context for an agent execution."""
    session_id: str
    org_id: str
    task_id: Optional[str]
    task_description: str
    memory: List[Dict] = field(default_factory=list)
    variables: Dict[str, Any] = field(default_factory=dict)


@dataclass
class ReasoningStep:
    """A single step in agent reasoning."""
    timestamp: datetime
    thought: str
    action: str  # "think", "tool_call", "respond", "ask_human"
    tool_name: Optional[str] = None
    tool_input: Optional[Dict] = None
    tool_output: Optional[Any] = None
    confidence: float = 1.0


class AgentRuntime:
    """
    Runtime environment for executing agents.

    Connects agents to LLMs, tools, and memory.
    Captures full reasoning traces for audit and learning.
    """

    def __init__(
        self,
        llm_gateway: LLMGateway,
        prompt_manager: PromptManager,
        event_store: EventStore,
        tool_registry: 'ToolRegistry'
    ):
        self.llm = llm_gateway
        self.prompts = prompt_manager
        self.events = event_store
        self.tools = tool_registry

    async def execute(
        self,
        config: AgentConfig,
        context: AgentContext,
        on_thought: Optional[callable] = None  # Callback for streaming thoughts
    ) -> Dict[str, Any]:
        """
        Execute an agent task.

        Returns the final result and reasoning trace.
        """
        reasoning_trace: List[ReasoningStep] = []
        messages: List[Message] = []

        # Build system prompt
        system_prompt = self._build_system_prompt(config, context)
        messages.append(Message(role=Role.SYSTEM, content=system_prompt))

        # Add task as user message
        messages.append(Message(
            role=Role.USER,
            content=f"Task: {context.task_description}"
        ))

        # Get available tools
        tools = self._get_tools(config.available_tools)

        # Execute reasoning loop
        for iteration in range(config.max_iterations):
            # Call LLM
            llm_config = LLMConfig(
                model=config.default_model,
                temperature=config.temperature
            )

            response = await self.llm.complete(
                messages=messages,
                config=llm_config,
                tools=tools
            )

            # Check for tool calls
            if response.tool_calls:
                for tool_call in response.tool_calls:
                    step = ReasoningStep(
                        timestamp=datetime.utcnow(),
                        thought=f"I need to use {tool_call['name']}",
                        action="tool_call",
                        tool_name=tool_call['name'],
                        tool_input=tool_call['arguments']
                    )

                    # Check autonomy level
                    if config.autonomy_level == "manual":
                        step.action = "ask_human"
                        reasoning_trace.append(step)
                        return self._create_approval_request(
                            context, step, reasoning_trace
                        )

                    elif config.autonomy_level == "supervised":
                        # Check if tool is high-risk
                        if self.tools.is_high_risk(tool_call['name']):
                            step.action = "ask_human"
                            reasoning_trace.append(step)
                            return self._create_approval_request(
                                context, step, reasoning_trace
                            )

                    # Execute tool
                    try:
                        tool_output = await self.tools.execute(
                            tool_call['name'],
                            tool_call['arguments'],
                            context
                        )
                        step.tool_output = tool_output
                    except Exception as e:
                        step.tool_output = f"Error: {str(e)}"

                    reasoning_trace.append(step)

                    if on_thought:
                        await on_thought(step)

                    # Add tool result to messages
                    messages.append(Message(
                        role=Role.ASSISTANT,
                        content="",
                        tool_calls=[tool_call]
                    ))
                    messages.append(Message(
                        role=Role.TOOL,
                        content=json.dumps(step.tool_output),
                        tool_call_id=tool_call['id']
                    ))

            else:
                # No tool calls - agent is responding
                step = ReasoningStep(
                    timestamp=datetime.utcnow(),
                    thought=response.content,
                    action="respond"
                )
                reasoning_trace.append(step)

                if on_thought:
                    await on_thought(step)

                # Check if agent is done
                if self._is_complete(response.content):
                    break

                messages.append(Message(
                    role=Role.ASSISTANT,
                    content=response.content
                ))

        # Save reasoning trace as event
        await self._save_trace(context, reasoning_trace)

        return {
            "session_id": context.session_id,
            "result": reasoning_trace[-1].thought if reasoning_trace else "",
            "trace": reasoning_trace,
            "iterations": len(reasoning_trace)
        }

    def _build_system_prompt(
        self,
        config: AgentConfig,
        context: AgentContext
    ) -> str:
        """Build the complete system prompt for the agent."""
        parts = [config.persona_prompt]

        # Add relevant memory
        if context.memory:
            parts.append("\n## Relevant Context from Memory:")
            for item in context.memory[-5:]:  # Last 5 relevant items
                parts.append(f"- {item['content']}")

        # Add autonomy instructions
        if config.autonomy_level == "autonomous":
            parts.append("""
## Autonomy Level: AUTONOMOUS
You may execute actions without human approval. Use good judgment.
Only escalate if you encounter something unexpected or high-risk.
""")
        elif config.autonomy_level == "supervised":
            parts.append("""
## Autonomy Level: SUPERVISED
You may execute most actions autonomously.
High-risk actions (code deployment, data deletion, external API calls)
require human approval. Mark these with [APPROVAL_NEEDED].
""")
        else:
            parts.append("""
## Autonomy Level: MANUAL
All actions require human approval. Propose actions and wait for confirmation.
""")

        return "\n\n".join(parts)

    def _get_tools(self, tool_names: List[str]) -> List[ToolDefinition]:
        """Get tool definitions for available tools."""
        return [
            self.tools.get_definition(name)
            for name in tool_names
            if self.tools.has(name)
        ]

    def _is_complete(self, content: str) -> bool:
        """Check if the agent indicates task completion."""
        completion_indicators = [
            "task complete",
            "task completed",
            "finished",
            "done",
            "[COMPLETE]"
        ]
        content_lower = content.lower()
        return any(ind in content_lower for ind in completion_indicators)

    def _create_approval_request(
        self,
        context: AgentContext,
        step: ReasoningStep,
        trace: List[ReasoningStep]
    ) -> Dict:
        """Create a human approval request."""
        return {
            "session_id": context.session_id,
            "status": "awaiting_approval",
            "approval_request": {
                "action": step.tool_name,
                "arguments": step.tool_input,
                "reason": step.thought
            },
            "trace": trace
        }

    async def _save_trace(
        self,
        context: AgentContext,
        trace: List[ReasoningStep]
    ):
        """Save reasoning trace as an event for learning."""
        await self.events.append(
            stream_id=f"agent-session:{context.session_id}",
            event_type="AgentReasoningCompleted",
            data={
                "session_id": context.session_id,
                "task_id": context.task_id,
                "trace": [
                    {
                        "timestamp": step.timestamp.isoformat(),
                        "thought": step.thought,
                        "action": step.action,
                        "tool_name": step.tool_name,
                        "tool_input": step.tool_input,
                        "tool_output": str(step.tool_output)[:1000]  # Truncate
                    }
                    for step in trace
                ]
            },
            expected_version=-1,
            metadata={"org_id": context.org_id}
        )
```

### 8. Tool Registry

```python
# company_os/agents/tools.py

from typing import Any, Callable, Dict, List, Optional
from dataclasses import dataclass

from company_os.core.llm.provider import ToolDefinition


@dataclass
class Tool:
    """A tool that agents can use."""
    name: str
    description: str
    parameters: Dict[str, Any]  # JSON Schema
    handler: Callable
    high_risk: bool = False
    requires_approval: List[str] = None  # Autonomy levels requiring approval


class ToolRegistry:
    """
    Registry of tools available to agents.

    Tools are functions that agents can call.
    """

    def __init__(self):
        self._tools: Dict[str, Tool] = {}

    def register(
        self,
        name: str,
        description: str,
        parameters: Dict[str, Any],
        handler: Callable,
        high_risk: bool = False
    ):
        """Register a new tool."""
        self._tools[name] = Tool(
            name=name,
            description=description,
            parameters=parameters,
            handler=handler,
            high_risk=high_risk
        )

    def has(self, name: str) -> bool:
        return name in self._tools

    def is_high_risk(self, name: str) -> bool:
        tool = self._tools.get(name)
        return tool.high_risk if tool else True

    def get_definition(self, name: str) -> ToolDefinition:
        """Get tool definition for LLM."""
        tool = self._tools[name]
        return ToolDefinition(
            name=tool.name,
            description=tool.description,
            parameters=tool.parameters
        )

    async def execute(
        self,
        name: str,
        arguments: Dict[str, Any],
        context: Any
    ) -> Any:
        """Execute a tool."""
        tool = self._tools.get(name)
        if not tool:
            raise ValueError(f"Unknown tool: {name}")

        return await tool.handler(arguments, context)


# Register built-in tools
def create_default_tools() -> ToolRegistry:
    """Create registry with default tools."""
    registry = ToolRegistry()

    # Web search tool
    registry.register(
        name="web_search",
        description="Search the web for information",
        parameters={
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search query"
                },
                "num_results": {
                    "type": "integer",
                    "default": 5
                }
            },
            "required": ["query"]
        },
        handler=web_search_handler,
        high_risk=False
    )

    # File read tool
    registry.register(
        name="read_file",
        description="Read contents of a file",
        parameters={
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "File path to read"
                }
            },
            "required": ["path"]
        },
        handler=read_file_handler,
        high_risk=False
    )

    # Code execution tool (HIGH RISK)
    registry.register(
        name="execute_code",
        description="Execute Python code in a sandbox",
        parameters={
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "Python code to execute"
                }
            },
            "required": ["code"]
        },
        handler=execute_code_handler,
        high_risk=True  # Requires approval
    )

    return registry


async def web_search_handler(args: Dict, context: Any) -> List[Dict]:
    """Perform web search."""
    # Implement with your preferred search API
    # (SerpAPI, Brave Search, etc.)
    pass


async def read_file_handler(args: Dict, context: Any) -> str:
    """Read file contents."""
    path = args['path']
    # Validate path is within allowed directories
    # Read and return contents
    pass


async def execute_code_handler(args: Dict, context: Any) -> str:
    """Execute code in sandbox."""
    # Execute in Docker container with resource limits
    pass
```

---

## Configuration

```yaml
# config/llm.yaml

providers:
  anthropic:
    enabled: true
    api_key: "${ANTHROPIC_API_KEY}"
    default_model: "claude-3.5-sonnet"
    rate_limit_rpm: 50
    fallback_provider: "openai"

  openai:
    enabled: true
    api_key: "${OPENAI_API_KEY}"
    default_model: "gpt-4o"
    rate_limit_rpm: 60
    fallback_provider: null

# Agent-specific model assignments
agent_models:
  researcher:
    primary: "anthropic"
    model: "claude-3.5-sonnet"  # Good for analysis
  implementer:
    primary: "anthropic"
    model: "claude-3.5-sonnet"  # Good for code
  architect:
    primary: "anthropic"
    model: "claude-3-opus"      # Best reasoning for design
```

---

## Key Benefits

### 1. **Provider Independence**
- Switch between Claude/GPT without code changes
- Automatic fallback on failures
- Cost optimization by model selection

### 2. **Full Observability**
- Every LLM call is tracked
- Reasoning traces stored as events
- Cost monitoring per provider

### 3. **Prompt Management**
- Version-controlled prompts
- Template variables for customization
- Few-shot examples support

### 4. **Tool Integration**
- Declarative tool definitions
- Risk-based approval workflow
- Sandboxed execution

### 5. **Production Ready**
- Rate limiting
- Retry with backoff
- Error handling

---

**Next Document: Authentication & Security Foundation →**
