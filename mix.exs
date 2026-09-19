defmodule AuditTrailEx.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/hata/audit_trail_ex"

  def project do
    [
      app: :audit_trail_ex,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:prod), do: ["lib"]
  defp elixirc_paths(_), do: ["lib", "test/support"]

  defp deps do
    [
      {:ecto_sql, "~> 3.11"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:postgrex, ">= 0.0.0", only: [:dev, :test]},
      {:plug, "~> 1.16", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    AuditTrailEx provides reusable, transaction-safe audit logging, field-level diffing,
    actor tracking, and change-history capabilities for Elixir applications using Ecto.
    """
  end

  defp package do
    [
      name: "audit_trail_ex",
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md CONTRIBUTING.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "AuditTrailEx",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md", "LICENSE"],
      groups_for_modules: [
        Core: [
          AuditTrailEx,
          AuditTrailEx.Event,
          AuditTrailEx.Multi
        ],
        "Change Tracking": [
          AuditTrailEx.Diff,
          AuditTrailEx.Serializer,
          AuditTrailEx.Filter,
          AuditTrailEx.Formatter
        ],
        Integration: [
          AuditTrailEx.Actor,
          AuditTrailEx.Query,
          AuditTrailEx.Migration,
          AuditTrailEx.Telemetry,
          AuditTrailEx.Web
        ]
      ]
    ]
  end
end
