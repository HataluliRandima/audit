# Contributing to AuditTrailEx

Thank you for your interest in contributing to AuditTrailEx! We welcome pull requests, bug reports, and architectural improvements from the open-source community.

## Code of Conduct

Please be respectful and constructive in all discussions, issues, and pull requests.

## Development Workflow

### 1. Prerequisites
- Elixir 1.14+
- Erlang/OTP 25+
- PostgreSQL 14+ (or Docker)

### 2. Environment Setup
Clone the repository and install dependencies:

```bash
git clone https://github.com/hata/audit_trail_ex.git
cd audit_trail_ex
mix deps.get
```

Start the PostgreSQL test database (Docker example):

```bash
docker run --name audit_trail_postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_DB=audit_trail_ex_test \
  -p 5432:5432 -d postgres:16-alpine
```

### 3. Running Tests
Run the ExUnit test suite:

```bash
mix test
```

Run the demo script:

```bash
MIX_ENV=test mix run examples/demo.exs
```

### 4. Code Quality & Standards
Before opening a pull request, ensure all checks pass:

```bash
# Check code formatting
mix format --check-formatted

# Run static code analysis with Credo
mix credo --strict

# Verify documentation generation
mix docs
```

### 5. Architectural Guidelines
- **Originality**: AuditTrailEx is 100% clean-room open-source code. Do not copy or paste proprietary internal code.
- **Framework Independence**: Keep the core library free of hard Phoenix/Plug dependencies.
- **Transaction Safety**: Any database mutation must maintain transactional atomicity with its audit event.
- **Data Security**: Never log unredacted passwords, tokens, or configured sensitive fields. Ensure Telemetry metadata never leaks field values.
- **Performance**: Ensure audit tables have appropriate indexes and do not introduce N+1 queries.

## Submitting Pull Requests
1. Fork the repository and create a new feature branch (`git checkout -b feature/my-enhancement`).
2. Add relevant ExUnit tests for any new functionality or bug fixes.
3. Keep commit messages clear and concise.
4. Ensure CI tests and quality checks pass.
5. Open a Pull Request on GitHub with a description of the changes.

