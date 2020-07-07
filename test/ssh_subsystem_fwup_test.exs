defmodule SSHSubsystemFwupTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  # doctest SSHSubsystemFwup

  @port 10123
  @tmpdir Path.join(System.tmp_dir!(), "ssh_subsystem_fwup")

  setup_all do
    File.mkdir_p!(@tmpdir)
  end

  def start_sshd(options) do
    {:ok, ref} =
      :ssh.daemon(@port, [
        {:max_sessions, 1},
        {:user_passwords, [{'user', 'password'}]},
        {:system_dir, 'test/fixtures'},
        {:subsystems, [SSHSubsystemFwup.subsystem_spec(options)]}
      ])

    on_exit(fn ->
      :ssh.stop_daemon(ref)

      devpath = options[:devpath]
      devpath && File.rm!(devpath)
    end)
  end

  def do_ssh(payload) do
    connect_opts = [silently_accept_hosts: true, user: 'user', password: 'password']

    {:ok, connection_ref} = :ssh.connect(:localhost, @port, connect_opts)
    {:ok, channel_id} = :ssh_connection.session_channel(connection_ref, 500)
    :success = :ssh_connection.subsystem(connection_ref, channel_id, 'fwup', 500)

    # Sending data can fail if the remote side closes first. That's what happens
    # when the remote reports a fatal error and that's expected.
    _ = :ssh_connection.send(connection_ref, channel_id, payload)
    _ = :ssh_connection.send_eof(connection_ref, channel_id)

    wait_for_complete(connection_ref, channel_id, {"", -1})
  end

  defp wait_for_complete(connection_ref, channel_id, {result, exit_status} = rc) do
    receive do
      {:ssh_cm, ^connection_ref, {:data, 0, 0, message}} ->
        wait_for_complete(connection_ref, channel_id, {result <> message, exit_status})

      {:ssh_cm, ^connection_ref, {:eof, 0}} ->
        wait_for_complete(connection_ref, channel_id, rc)

      {:ssh_cm, ^connection_ref, {:exit_status, 0, status}} ->
        wait_for_complete(connection_ref, channel_id, {result, status})

      {:ssh_cm, ^connection_ref, {:closed, 0}} ->
        rc
    after
      1000 ->
        raise RuntimeError, "ssh timed out?"
    end
  end

  defp default_options(name) do
    [
      success_callback: {Kernel, :send, [self(), :success]},
      devpath: Path.join(@tmpdir, "#{name}.img")
    ]
  end

  test "successful update", context do
    options = default_options(context.test)
    File.touch!(options[:devpath])
    start_sshd(options)

    fw_contents = SSHSubsystemFwup.Support.Fwup.create_firmware()

    capture_log(fn ->
      {output, exit_status} = do_ssh(fw_contents)

      assert exit_status == 0
      assert output =~ "Success!"
    end)

    # Check that the success function was called
    assert_receive :success

    # Check that the update was applied
    assert match?(<<"Hello, world!", _::binary()>>, File.read!(options[:devpath]))
  end

  test "failed update", context do
    options = default_options(context.test)
    File.touch!(options[:devpath])

    start_sshd(options)
    fw_contents = SSHSubsystemFwup.Support.Fwup.create_corrupt_firmware()

    capture_log(fn ->
      {_output, exit_status} = do_ssh(fw_contents)

      assert exit_status == 1
    end)

    refute_receive :success
  end

  test "overriding the fwup task", context do
    options = default_options(context.test) ++ [task: "complete"]
    File.touch!(options[:devpath])

    start_sshd(options)
    fw_contents = SSHSubsystemFwup.Support.Fwup.create_firmware(task: "complete")

    capture_log(fn ->
      {output, exit_status} = do_ssh(fw_contents)

      assert exit_status == 0
      assert output =~ "Success!"
    end)

    # Check that the success function was called
    assert_receive :success

    # Check that the update was applied
    assert match?(<<"Hello, world!", _::binary()>>, File.read!(options[:devpath]))
  end

  test "unspecified devpath is an error" do
    start_sshd([])
    fw_contents = SSHSubsystemFwup.Support.Fwup.create_firmware(task: "complete")

    {output, exit_status} = do_ssh(fw_contents)

    assert exit_status != 0
    assert output =~ "fwup devpath is invalid"
  end
end
