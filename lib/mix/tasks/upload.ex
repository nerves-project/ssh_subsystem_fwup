defmodule Mix.Tasks.Upload do
  use Mix.Task

  @shortdoc "Uploads firmware to a Nerves device over SSH"

  @moduledoc """
  Upgrade the firmware on a Nerves device using SSH.

  By default, `mix upload` reads the firmware built by the current `MIX_ENV`
  and `MIX_TARGET` settings, and sends it to `nerves.local`. Pass in a another
  hostname to send the firmware elsewhere.

  NOTE: This implementation cannot ask for passphrases, and therefore, cannot
  connect to devices protected by username/passwords or decrypt
  password-protected private keys. One workaround is to use the `ssh-agent` to
  pass credentials.

  ## Command line options

   * `--firmware` - The path to a fw file

  ## Examples

  Upgrade a Raspberry Pi Zero at `nerves.local`:

      MIX_TARGET=rpi0 mix upload nerves.local

  Upgrade `192.168.1.120` and explicitly pass the `.fw` file:

      mix upload 192.168.1.120 --firmware _build/rpi0_prod/nerves/images/app.fw

  """

  @switches [
    firmware: :string
  ]

  @doc false
  @spec run([String.t()]) :: :ok
  def run(argv) do
    {opts, args, unknown} = OptionParser.parse(argv, strict: @switches)

    if unknown != [] do
      [{param, _} | _] = unknown
      Mix.raise("unknown parameter passed to mix upload: #{param}")
    end

    ip =
      case args do
        [address] ->
          address

        [] ->
          "nerves.local"

        _other ->
          Mix.raise(target_ip_address_or_name_msg())
      end

    firmware_path = firmware(opts)

    Mix.shell().info("""
    Path: #{firmware_path}
    #{maybe_print_firmware_uuid(firmware_path)}
    Uploading to #{ip}...
    """)

    user = Process.whereis(:user)
    Process.unregister(:user)

    # Take over STDIN in case SSH requires inputting password
    stdin_port = Port.open({:spawn, "tty_sl -c -e"}, [:binary, :eof, :stream, :in])
    _ = Application.stop(:logger)

    shell = System.get_env("SHELL")

    # Options:
    #
    # ConnectTimeout - don't wait forever to connect
    command = "cat #{firmware_path} | #{ssh_path()} -o ConnectTimeout=3 -s #{ip} fwup"

    port =
      Port.open({:spawn, ~s(script -q /dev/null #{shell} -c "#{command}")}, [
        :binary,
        :exit_status,
        :stream,
        :stderr_to_stdout,
        {
          :env,
          # pass the whole user env
          for({k, v} <- System.get_env(), do: {to_charlist(k), to_charlist(v)})
        }
      ])

    Process.register(user, :user)
    Process.flag(:trap_exit, true)

    shell_loop(stdin_port, port)

    # Close the ports if they are still around
    if Port.info(stdin_port), do: Port.close(stdin_port)
    if Port.info(port), do: Port.close(port)
    
    :ok
  end

  defp shell_loop(stdin_port, ssh_port) do
    receive do
      # Route input from stdin to the command port
      {^stdin_port, {:data, data}} ->
        Port.command(ssh_port, data)
        shell_loop(stdin_port, ssh_port)

      # Route output from the command port to stdout
      {^ssh_port, {:data, data}} ->
        IO.write(data)
        shell_loop(stdin_port, ssh_port)

      # If any of the ports get closed, break out of the loop
      {^ssh_port, :eof} ->
        :ok

      {^ssh_port, {:exit_status, 0}} ->
        :ok

      {_port, {:exit_status, status}} ->
        Mix.raise("ssh failed with status #{status}")

      {:EXIT, ^ssh_port, reason} ->
        Mix.raise("""
        Unexpected exit from ssh (#{inspect(reason)})

        This is known to happen when ssh interactively prompts you for a
        passphrase. The following are workarounds:

        1. Load your private key identity into the ssh agent by running
            `ssh-add`

        2. Use the `upload.sh` script. Create one by running
            `mix firmware.gen.script`.
        """)

      other ->
        Mix.raise("""
        Unexpected message received: #{inspect(other)}

        Please open an issue so that we can fix this.
        """)
    end
  end

  defp firmware(opts) do
    if fw = opts[:firmware] do
      fw |> Path.expand()
    else
      discover_firmware(opts)
    end
  end

  defp discover_firmware(_opts) do
    if Mix.target() == :host do
      Mix.raise("""
      You must call mix with a target set or pass the firmware's path

      Examples:

        $ MIX_TARGET=rpi0 mix upload nerves.local

      or

        $ mix upload nerves.local --firmware _build/rpi0_prod/nerves/images/app.fw
      """)
    end

    build_path = Mix.Project.build_path()
    app = Mix.Project.config()[:app]

    Path.join([build_path, "nerves", "images", "#{app}.fw"])
    |> Path.expand()
  end

  defp ssh_path() do
    case System.find_executable("ssh") do
      nil ->
        Mix.raise("""
        Cannot find 'ssh'. Check that it exists in your path
        """)

      path ->
        to_charlist(path)
    end
  end

  defp target_ip_address_or_name_msg() do
    ~S"""
    mix upload expects a target IP address or hostname

    Example:

      If the device is reachable using `nerves-1234.local`, try:

      `mix upload nerves-1234.local`
    """
  end

  defp maybe_print_firmware_uuid(fw_path) do
    fwup = System.find_executable("fwup")
    {uuid, 0} = System.cmd(fwup, ["-m", "--metadata-key", "meta-uuid", "-i", fw_path])
    "UUID: #{uuid}\n"
  catch
    # fwup may not be on the host or something else failed, but continue
    # on as normal by returning an empty line
    _, _ -> ""
  end
end
