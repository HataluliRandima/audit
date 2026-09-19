defmodule AuditTrailEx.Web do
  @moduledoc """
  Optional helpers for extracting web request metadata from `Plug.Conn` or Phoenix requests.

  This module is completely decoupled from Phoenix and operates safely whether Plug
  is present or absent.
  """

  @doc """
  Extracts contextual metadata from a `Plug.Conn` or request map.

  Captured metadata:
    * `:request_id` - from `"x-request-id"` header
    * `:remote_ip` - string formatted client IP address
    * `:user_agent` - from `"user-agent"` header
    * `:method` - HTTP method
    * `:request_path` - requested URI path
    * `:controller` - Phoenix controller module (if available)
    * `:action` - Phoenix action name (if available)

  ## Examples

      # In a controller or Phoenix pipeline:
      metadata = AuditTrailEx.Web.extract_metadata(conn)
      AuditTrailEx.update(Repo, changeset, actor: current_user, metadata: metadata)
  """
  @spec extract_metadata(term()) :: map()
  def extract_metadata(%{__struct__: struct} = conn)
      when struct in [Plug.Conn] do
    request_id = get_req_header_val(conn, "x-request-id")
    user_agent = get_req_header_val(conn, "user-agent")
    remote_ip = format_ip(Map.get(conn, :remote_ip))

    base = %{
      "source" => "web",
      "method" => to_string(Map.get(conn, :method)),
      "request_path" => Map.get(conn, :request_path)
    }

    base
    |> maybe_put("request_id", request_id)
    |> maybe_put("remote_ip", remote_ip)
    |> maybe_put("user_agent", user_agent)
    |> extract_phoenix_metadata(conn)
  end

  def extract_metadata(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  def extract_metadata(_other), do: %{}

  defp get_req_header_val(conn, header_name) do
    if function_exported?(Plug.Conn, :get_req_header, 2) do
      case Plug.Conn.get_req_header(conn, header_name) do
        [val | _] -> val
        _ -> nil
      end
    else
      nil
    end
  end

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp format_ip({a, b, c, d, e, f, g, h}) do
    "#{Integer.to_string(a, 16)}:#{Integer.to_string(b, 16)}:#{Integer.to_string(c, 16)}:" <>
      "#{Integer.to_string(d, 16)}:#{Integer.to_string(e, 16)}:#{Integer.to_string(f, 16)}:" <>
      "#{Integer.to_string(g, 16)}:#{Integer.to_string(h, 16)}"
  end

  defp format_ip(_), do: nil

  defp extract_phoenix_metadata(metadata, conn) do
    private = Map.get(conn, :private, %{})
    controller = Map.get(private, :phoenix_controller)
    action = Map.get(private, :phoenix_action)

    metadata
    |> maybe_put("controller", controller && inspect(controller))
    |> maybe_put("action", action && to_string(action))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
