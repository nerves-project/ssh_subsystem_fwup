defmodule NervesFirmwareSSH2.MixProject do
  use Mix.Project

  @version "0.4.4"
  @source_url "https://github.com/nerves-project/nerves_firmware_ssh2"

  def project do
    [
      app: :nerves_firmware_ssh2,
      version: @version,
      description: description(),
      package: package(),
      source_url: @source_url,
      elixir: "~> 1.8",
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        flags: [:error_handling, :race_conditions, :underspecs]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger, :ssh]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "Perform over-the-air updates to Nerves devices using ssh"
  end

  defp package do
    %{
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    }
  end

  defp deps do
    [
      {:ex_doc, "~> 0.19", only: :docs, runtime: false},
      {:dialyxir, "~> 1.0.0-rc.6", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      extras: ["README.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
