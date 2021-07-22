defmodule SSHSubsystemFwup.Support.Fwup do
  @moduledoc """
  This module is intended to help with testing and development
  by allowing for "easy" creation of firmware signing keys, and
  signed/unsigned/corrupted firmware files.

  It is a thin wrapper around `fwup`, and it persists the files in
  `System.tmp_dir()`.

  The files are given the names that are passed to the respective functions, so
  make sure you pass unique names to avoid collisions if necessary.  This module
  takes little effort to avoid collisions on its own.
  """

  @doc """
  Create an unsigned firmware image and return it as a binary
  """
  @spec create_firmware(keyword()) :: binary()
  def create_firmware(options \\ []) do
    out_path = tmp_path(".fw")
    conf_path = make_conf(options)

    {_, 0} =
      System.cmd("fwup", [
        "-c",
        "-f",
        conf_path,
        "-o",
        out_path
      ])

    File.rm!(conf_path)
    contents = File.read!(out_path)
    File.rm!(out_path)

    contents
  end

  @doc """
  Just like create_firmware, but corrupted
  """
  @spec create_corrupt_firmware(keyword()) :: nonempty_binary()
  def create_corrupt_firmware(options \\ []) do
    <<start::binary-size(32), finish::binary>> = create_firmware(options)
    <<start::binary, 1, finish::binary>>
  end

  defp tmp_path(suffix) do
    Path.join([System.tmp_dir(), "#{random_string()}#{suffix}"])
  end

  defp make_conf(options) do
    path = tmp_path(".conf")
    File.write!(path, build_conf_contents(options))
    path
  end

  defp build_conf_contents(options) do
    task = Keyword.get(options, :task, "upgrade")
    message = Keyword.get(options, :message, "Hello, world!")

    """
    meta-product = "Test firmware"
    meta-description = "Try to test ssh_subsystem_fwup"
    meta-version = "0.1.0"
    meta-platform = "rpi3"
    meta-architecture = "arm"
    meta-author = "Me"

    file-resource test.txt {
    contents = "#{message}"
    }

    task #{task} {
      on-resource test.txt { raw_write(0) }
    }
    """
  end

  defp random_string() do
    Integer.to_string(:rand.uniform(0x100000000), 36) |> String.downcase()
  end
end
