defmodule NervesSSH.Agent do
  @behaviour :ssh_client_key_api

  def add_host_key(host, publicKey, options) do
    IO.inspect(host, label: "[add_host_key/3] host")
    IO.inspect(publicKey, label: "[add_host_key/3] publicKey")
    IO.inspect(options, label: "[add_host_key/3] options")
    :ssh_agent.add_host_key(host, publicKey, options)
  end

  def add_host_key(host, port, publicKey, options) do
    IO.inspect(host, label: "[add_host_key/4] host")
    IO.inspect(port, label: "[add_host_key/4] port")
    IO.inspect(publicKey, label: "[add_host_key/4] publicKey")
    IO.inspect(options, label: "[add_host_key/4] options")
    :ssh_agent.add_host_key(host, port, publicKey, options)
  end

  def is_host_key(key, host, algorithm, options) do
    IO.inspect(key, label: "[is_host_key/4] key")
    IO.inspect(host, label: "[is_host_key/4] host")
    IO.inspect(algorithm, label: "[is_host_key/4] algorithm")
    IO.inspect(options, label: "[is_host_key/4] options")
    :ssh_agent.is_host_key(key, host, algorithm, options)
  end

  def is_host_key(key, host, port, algorithm, options) do
    IO.inspect(key, label: "[is_host_key/5] key")
    IO.inspect(host, label: "[is_host_key/5] host")
    IO.inspect(port, label: "[is_host_key/5] port")
    IO.inspect(algorithm, label: "[is_host_key/5] algorithm")
    IO.inspect(options, label: "[is_host_key/5] options")
    :ssh_agent.is_host_key(key, host, port, algorithm, options) |> IO.inspect(label: "RESULT:")
  end

  def user_key(algorithm, options) do
    IO.inspect(algorithm, label: "[user_key] algorithm")
    IO.inspect(options, label: "[user_key] options")
    :ssh_agent.user_key(algorithm, options) |> IO.inspect(label: "[user_key] result")
  end

  # defdelegate sign(key, sig, opts), to: :ssh_agent

  def sign(key, sig, opts) do
    IO.inspect(key, label: "KEY")
    IO.inspect(sig, label: "sig")
    IO.inspect(opts, label: "opts")
    :ssh_agent.sign(key, sig, opts) |> IO.inspect(label: "SIGNED", limit: :infinity)
  end
end
