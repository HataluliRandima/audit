defmodule AuditTrailEx.Filter do
  @moduledoc """
  Manages filtering and redacting sensitive data in audit logs.

  Fields can be either:
    * **Excluded**: Completely removed from the audit changes map.
    * **Redacted**: Replaced with `"[REDACTED]"` in the audit changes map.

  ## Configuration Hierarchy

  Configurations are merged with the following priority (highest to lowest):
  1. Per-operation options (e.g., `excluded_fields: [:token]` passed to `AuditTrailEx.update/3`)
  2. Schema-specific configuration via `__audit_trail_options__/0` callback
  3. Global application environment (`config :audit_trail_ex, ...`)

  ## Examples

      # In config/config.exs:
      config :audit_trail_ex,
        excluded_fields: [:password, :password_hash, :api_secret],
        redacted_fields: [:credit_card, :ssn]

      # Per-schema callback:
      defmodule MyApp.Accounts.User do
        use Ecto.Schema

        def __audit_trail_options__ do
          [
            excluded_fields: [:temporary_pin],
            redacted_fields: [:email]
          ]
        end
      end
  """

  @default_redaction_text "[REDACTED]"

  @doc """
  Filters and redacts a map of calculated field changes.

  Expects a map where each key is a string field name and value is `%{from: _, to: _}`.
  """
  @spec filter_changes(map(), module() | nil, keyword()) :: map()
  def filter_changes(changes, schema, opts \\ []) when is_map(changes) do
    excluded = resolved_fields(:excluded_fields, schema, opts)
    redacted = resolved_fields(:redacted_fields, schema, opts)
    redaction_text = Keyword.get(opts, :redaction_text, @default_redaction_text)

    changes
    |> Enum.reject(fn {field, _diff} ->
      field_matches?(field, excluded)
    end)
    |> Enum.map(fn {field, diff} ->
      if field_matches?(field, redacted) do
        {field, redact_diff(diff, redaction_text)}
      else
        {field, diff}
      end
    end)
    |> Map.new()
  end

  @doc """
  Checks if a field is excluded for a given schema and options.
  """
  @spec excluded?(atom() | String.t(), module() | nil, keyword()) :: boolean()
  def excluded?(field, schema, opts \\ []) do
    field_matches?(field, resolved_fields(:excluded_fields, schema, opts))
  end

  @doc """
  Checks if a field is redacted for a given schema and options.
  """
  @spec redacted?(atom() | String.t(), module() | nil, keyword()) :: boolean()
  def redacted?(field, schema, opts \\ []) do
    field_matches?(field, resolved_fields(:redacted_fields, schema, opts))
  end

  defp resolved_fields(key, schema, opts) do
    global = Application.get_env(:audit_trail_ex, key, [])
    schema_opts = schema_options(schema)
    schema_fields = Keyword.get(schema_opts, key, [])
    call_fields = Keyword.get(opts, key, [])

    (global ++ schema_fields ++ call_fields)
    |> Enum.map(&to_string/1)
    |> MapSet.new()
  end

  defp schema_options(nil), do: []

  defp schema_options(schema) when is_atom(schema) do
    if Code.ensure_loaded?(schema) and function_exported?(schema, :__audit_trail_options__, 0) do
      schema.__audit_trail_options__()
    else
      []
    end
  end

  defp schema_options(_), do: []

  defp field_matches?(field, field_set) do
    MapSet.member?(field_set, to_string(field))
  end

  defp redact_diff(%{from: from, to: to}, text) do
    %{
      from: if(is_nil(from), do: nil, else: text),
      to: if(is_nil(to), do: nil, else: text)
    }
  end

  defp redact_diff(%{"from" => from, "to" => to}, text) do
    %{
      "from" => if(is_nil(from), do: nil, else: text),
      "to" => if(is_nil(to), do: nil, else: text)
    }
  end

  defp redact_diff(other, text) when is_map(other) do
    Map.new(other, fn {k, v} -> {k, if(is_nil(v), do: nil, else: text)} end)
  end
end
