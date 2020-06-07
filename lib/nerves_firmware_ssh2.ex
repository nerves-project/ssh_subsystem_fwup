defmodule NervesFirmwareSSH2 do
  @moduledoc """
  This project contains the necessary infrastructure to support "over-the-air"
  firmware updates with Nerves by using
  [ssh](https://en.wikipedia.org/wiki/Secure_Shell).
  """

  @type options :: [
          fwup_path: Path.t(),
          devpath: Path.t(),
          task: String.t(),
          success_callback: mfa(),
          subsystem: charlist()
        ]

  @doc """
  Return a subsystem spec for use with `ssh:daemon/[1,2,3]`

  Options:

  * `:devpath` - the path for fwup to upgrade
  * `:fwup_path` - path to the fwup firmware update utility
  * `:success_callback` - an MFA to call when a firmware update completes
    successfully. Defaults to `{Nerves.Runtime, :reboot, []}`.
  * `:task` - the task to run in the firmware update. Defaults to `"upgrade"`
  * `:subsystem` - the ssh subsystem name. Defaults to 'nerves_firmware_ssh2'
  """
  @spec subsystem_spec(options()) :: :ssh.subsystem_spec()
  def subsystem_spec(options \\ []) do
    subsystem_name = Keyword.get(options, :subsystem, 'nerves_firmware_ssh2') |> to_charlist()

    {subsystem_name, {NervesFirmwareSSH2.Handler, options}}
  end
end
