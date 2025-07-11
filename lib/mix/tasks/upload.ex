# SPDX-FileCopyrightText: 2020 Frank Hunleth
# SPDX-FileCopyrightText: 2022 Jon Carstens
# SPDX-FileCopyrightText: 2024 Benjamin Milde
# SPDX-FileCopyrightText: 2024 Jon Ringle
#
# SPDX-License-Identifier: Apache-2.0
#
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

    # Options:
    #
    # ConnectTimeout - don't wait forever to connect
    # PreferredAuthentications=publickey - since keyboard interactivity doesn't
    #                                     work, don't try password entry options.
    # -T - No pseudoterminals since they're not needed for firmware updates
    opts = [
      :stream,
      :binary,
      :exit_status,
      :hide,
      :use_stdio,
      {:args,
       [
         "-o",
         "ConnectTimeout=3",
         "-o",
         "PreferredAuthentications=publickey",
         "-T",
         "-s",
         ip,
         "fwup"
       ]},
      {:env,
       [
         {~c"LD_LIBRARY_PATH", false}
       ]}
    ]

    port = Port.open({:spawn_executable, ssh_path()}, opts)

    fd = File.open!(firmware_path, [:read])

    Process.flag(:trap_exit, true)

    sender_pid = spawn_link(fn -> send_data(port, fd) end)
    port_read(port, sender_pid)
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

  defp port_read(port, sender_pid) do
    receive do
      {^port, {:data, data}} ->
        IO.write(data)
        port_read(port, sender_pid)

      {^port, {:exit_status, 0}} ->
        :ok

      {^port, {:exit_status, status}} ->
        Mix.raise("ssh failed with status #{status}")

      {:EXIT, ^sender_pid, :normal} ->
        # All data has been sent
        port_read(port, sender_pid)

      {:EXIT, ^port, reason} ->
        Mix.raise("""
        Unexpected exit from ssh (#{inspect(reason)})

        This is known to happen when ssh interactively prompts you for a
        passphrase. The following are workarounds:

        1. Make sure host key verification works for the hostname
           (try `ssh hostname`). This would apply when connecting to
           the device for the first time or for the first time after
           a fresh firmware was burned.

        2. Load your private key identity into the ssh agent by running
           `ssh-add`

        3. Use the `upload.sh` script. Create one by running
           `mix firmware.gen.script`.
        """)

      other ->
        Mix.raise("""
        Unexpected message received: #{inspect(other)}

        Please open an issue so that we can fix this.
        """)
    end
  end

  defp send_data(port, fd) do
    case IO.binread(fd, 16384) do
      :eof ->
        :ok

      {:error, _reason} ->
        exit(:read_failed)

      data ->
        Port.command(port, data)
        send_data(port, fd)
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
