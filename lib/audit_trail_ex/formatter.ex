defmodule AuditTrailEx.ChangeDescription do
  @moduledoc """
  Structured representation of a single field change for human presentation.
  """

  @enforce_keys [:field, :kind, :summary]
  defstruct [:field, :from, :to, :kind, :summary]

  @type kind :: :added | :removed | :changed

  @type t :: %__MODULE__{
          field: String.t(),
          from: term(),
          to: term(),
          kind: kind(),
          summary: String.t()
        }
end

defmodule AuditTrailEx.Formatter do
  @moduledoc """
  Transforms audit events and raw changes into structured, human-readable descriptions.

  Avoids any hard coupling to HTML or specific UI frameworks while providing both
  structured data (`AuditTrailEx.ChangeDescription`) and formatted plain text.
  """

  alias AuditTrailEx.ChangeDescription
  alias AuditTrailEx.Event

  @doc """
  Produces a list of structured `AuditTrailEx.ChangeDescription` structs for an event or changes map.

  ## Examples

      iex> event = %AuditTrailEx.Event{changes: %{"email" => %{"from" => "old@ex.com", "to" => "new@ex.com"}}}
      iex> [desc] = AuditTrailEx.Formatter.describe(event)
      iex> desc.field
      "email"
      iex> desc.kind
      :changed
  """
  @spec describe(Event.t() | map()) :: [ChangeDescription.t()]
  def describe(%Event{changes: changes}), do: describe(changes)

  def describe(changes) when is_map(changes) do
    Enum.map(changes, fn {field, diff} ->
      from = get_diff_val(diff, :from)
      to = get_diff_val(diff, :to)
      kind = classify_change(from, to)
      summary = build_summary(field, from, to, kind)

      %ChangeDescription{
        field: to_string(field),
        from: from,
        to: to,
        kind: kind,
        summary: summary
      }
    end)
  end

  @doc """
  Formats an audit event or list of change descriptions into a plain-text multi-line string.
  """
  @spec to_text(Event.t() | [ChangeDescription.t()] | map()) :: String.t()
  def to_text(%Event{} = event) do
    descriptions = describe(event)
    header = "#{String.capitalize(event.action)} #{event.schema} [#{event.record_id}]"
    body = Enum.map_join(descriptions, "\n\n", &format_description/1)

    if body == "" do
      header
    else
      "#{header}\n\n#{body}"
    end
  end

  def to_text(descriptions) when is_list(descriptions) do
    Enum.map_join(descriptions, "\n\n", &format_description/1)
  end

  def to_text(changes) when is_map(changes) do
    changes |> describe() |> to_text()
  end

  defp format_description(%ChangeDescription{kind: :added, field: field, to: to}) do
    """
    #{humanize(field)} set
      Value: #{inspect(to)}
    """
    |> String.trim_trailing()
  end

  defp format_description(%ChangeDescription{kind: :removed, field: field, from: from}) do
    """
    #{humanize(field)} removed
      Previous: #{inspect(from)}
    """
    |> String.trim_trailing()
  end

  defp format_description(%ChangeDescription{field: field, from: from, to: to}) do
    """
    #{humanize(field)} changed
      From: #{inspect(from)}
      To:   #{inspect(to)}
    """
    |> String.trim_trailing()
  end

  defp classify_change(nil, _to), do: :added
  defp classify_change(_from, nil), do: :removed
  defp classify_change(_from, _to), do: :changed

  defp build_summary(field, _from, to, :added) do
    "#{humanize(field)} set to #{inspect(to)}"
  end

  defp build_summary(field, from, _to, :removed) do
    "#{humanize(field)} removed (was #{inspect(from)})"
  end

  defp build_summary(field, from, to, :changed) do
    "#{humanize(field)} changed from #{inspect(from)} to #{inspect(to)}"
  end

  defp get_diff_val(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp get_diff_val(_other, _key), do: nil

  defp humanize(field) do
    field
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
