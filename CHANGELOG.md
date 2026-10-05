# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security
- Virtual fields (e.g. `:password`) are no longer recorded in audit diffs or serialized Ecto schemas.
- Association changes (`has_many`, `belongs_to`, etc.) are no longer recorded; previously nested changesets, including their raw params, were stored in `changes`.

### Fixed
- Embedded schema changes are recorded as their applied values instead of raw `Ecto.Changeset` structs.
- Insert/delete of structs no longer record `Ecto.Association.NotLoaded` placeholders.

## [0.1.0] - 2026-09-19

### Added
- Core audit event schema (`AuditTrailEx.Event`) supporting UUID and integer primary keys, JSON/map storage, and microsecond UTC timestamps.
- Automated field-level diff calculation (`AuditTrailEx.Diff`) for `:insert`, `:update`, and `:delete` operations, omitting unchanged fields.
- Robust data serializer (`AuditTrailEx.Serializer`) handling Decimal, Date, Time, DateTime, NaiveDateTime, UUIDs, structs, and complex nested data structures.
- Sensitive-field filtering and redaction (`AuditTrailEx.Filter`) with global, per-schema, and per-call configuration precedence.
- Protocol-based actor resolution (`AuditTrailEx.Actor`) supporting Ecto structs, maps, IDs, custom types, and system background jobs.
- Direct repository functions (`AuditTrailEx.insert/3`, `update/3`, `delete/3`, `audit/3`) providing atomic transaction safety.
- First-class `Ecto.Multi` pipeline integration (`AuditTrailEx.Multi`).
- Composable query builders (`AuditTrailEx.Query`) for filtering audit logs by record, actor, action, and time range.
- Human-readable structured change formatting (`AuditTrailEx.Formatter` and `AuditTrailEx.ChangeDescription`).
- Telemetry event emissions (`[:audit_trail_ex, :event, :created]` and `[:audit_trail_ex, :diff, :calculated]`) with data-leak prevention.
- Reusable Ecto migration helper (`AuditTrailEx.Migration`) with recommended PostgreSQL composite and GIN indexes.
- Decoupled web request metadata extraction helper (`AuditTrailEx.Web`).
- Comprehensive ExUnit test suite, documentation, and demo script.

