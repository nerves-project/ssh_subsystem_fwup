defmodule SSHSubsystemFwupTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  # doctest SSHSubsystemFwup

  alias SSHSubsystemFwup.Support.Fwup

  @port 10123
  @tmpdir Path.join(System.tmp_dir!(), "ssh_subsystem_fwup")

  setup_all do
    File.mkdir_p!(@tmpdir)

    {version_str, 0} = System.cmd("fwup", ["--version"])
    version = version_str |> String.trim() |> Version.parse!()

    Version.match?(version, "~> 1.9.0") ||
      raise "fwup 1.9.0 or later is needed for the unit tests"

    :ok
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

    fw_contents = Fwup.create_firmware()

    capture_log(fn ->
      {output, exit_status} = do_ssh(fw_contents)

      assert output =~ "Success!"
      assert exit_status == 0
    end)

    # Check that the success function was called
    assert_receive :success

    # Check that the update was applied
    # First 512 bytes is "Hello, world!"
    # Second 512 bytes is encrypted stuff we check in another test
    assert match?(<<"Hello, world!", 0::size(3992), _::binary>>, File.read!(options[:devpath]))
  end

  test "successful update with environment variable", context do
    # This tests applying the environment variable to control filesystem encryption
    # It requires fwup 1.9.0 or later to work.
    options =
      [
        fwup_env: [
          {"SUPER_SECRET", "1234567890123456789012345678901234567890123456789012345678901234"}
        ]
      ] ++
        default_options(context.test)

    File.touch!(options[:devpath])
    start_sshd(options)

    fw_contents = Fwup.create_firmware()

    capture_log(fn ->
      {output, exit_status} = do_ssh(fw_contents)

      assert output =~ "Success!"
      assert exit_status == 0
    end)

    # Check that the success function was called
    assert_receive :success

    # Check that the update was applied
    # The first 512 bytes should be the Hello world
    # Second 512 bytes are encrypted with the secret key
    contents = File.read!(options[:devpath])

    # Trust that this is right (change the key to see that it has an effect)
    expected_encrypted =
      <<67, 27, 224, 226, 140, 132, 49, 166, 73, 233, 155, 228, 232, 140, 85, 22, 14, 117, 132,
        203, 46, 113, 244, 90, 116, 225, 91, 150, 93, 117, 119, 56, 201, 233, 163, 216, 176, 167,
        243, 29, 197, 129, 237, 239, 24, 192, 104, 107, 135, 24, 145, 196, 140, 144, 255, 190, 43,
        128, 143, 235, 199, 235, 29, 11, 53, 243, 90, 14, 97, 132, 148, 152, 179, 9, 149, 4, 192,
        168, 163, 35, 222, 202, 169, 200, 80, 112, 92, 223, 216, 125, 44, 24, 139, 112, 113, 70,
        245, 101, 41, 243, 162, 125, 121, 120, 73, 178, 121, 80, 88, 43, 76, 165, 49, 217, 155,
        149, 100, 41, 237, 87, 64, 100, 7, 244, 153, 213, 54, 249, 88, 119, 45, 22, 144, 178, 128,
        17, 85, 151, 155, 190, 224, 175, 20, 30, 191, 25, 133, 59, 88, 156, 132, 109, 188, 246,
        95, 246, 176, 41, 152, 212, 100, 187, 96, 139, 127, 98, 61, 253, 110, 97, 129, 30, 115,
        133, 4, 125, 106, 46, 100, 178, 173, 146, 90, 24, 114, 149, 0, 148, 56, 207, 142, 116,
        215, 5, 18, 150, 231, 20, 140, 187, 215, 131, 91, 58, 63, 109, 115, 157, 103, 66, 235, 93,
        91, 124, 12, 154, 148, 208, 130, 204, 139, 162, 68, 8, 13, 48, 52, 18, 19, 202, 183, 108,
        31, 46, 177, 243, 164, 2, 87, 201, 205, 94, 147, 40, 62, 217, 61, 70, 59, 58, 206, 176,
        119, 70, 175, 146, 161, 187, 28, 63, 42, 208, 253, 106, 230, 67, 253, 76, 177, 95, 26,
        137, 137, 121, 116, 151, 90, 148, 96, 228, 55, 220, 13, 182, 237, 185, 41, 219, 226, 98,
        92, 143, 75, 165, 76, 99, 148, 130, 57, 121, 135, 4, 181, 253, 93, 221, 166, 89, 189, 51,
        212, 177, 128, 79, 162, 5, 6, 250, 18, 246, 253, 116, 118, 241, 54, 37, 142, 160, 61, 234,
        120, 68, 197, 236, 135, 168, 159, 149, 249, 93, 43, 27, 148, 41, 180, 219, 81, 182, 181,
        75, 71, 143, 132, 88, 111, 74, 98, 59, 88, 227, 19, 84, 40, 156, 44, 98, 76, 189, 103,
        215, 183, 234, 95, 161, 72, 80, 43, 37, 54, 166, 58, 248, 187, 70, 173, 205, 248, 23, 5,
        37, 157, 75, 184, 117, 213, 101, 127, 70, 241, 207, 134, 195, 170, 238, 30, 237, 68, 229,
        31, 234, 23, 16, 73, 10, 101, 231, 198, 69, 10, 103, 144, 238, 190, 235, 214, 95, 93, 166,
        36, 176, 86, 229, 199, 175, 136, 208, 24, 193, 183, 83, 165, 136, 213, 177, 136, 235, 112,
        169, 191, 195, 35, 208, 106, 20, 58, 253, 56, 44, 36, 253, 210, 76, 56, 240, 120, 217, 45,
        253, 45, 240, 191, 34, 186, 195, 180, 250, 184, 112, 105, 216, 155, 69, 108, 197, 13, 199,
        158, 71, 250, 236, 137, 98, 193, 24, 2, 255, 120, 79, 142, 63, 205, 8, 142, 235, 14, 188,
        167, 240, 29, 164, 93, 192>>

    assert match?(
             <<"Hello, world!", 0::size(3992), ^expected_encrypted::512-bytes, _::binary>>,
             contents
           )
  end

  test "failed update", context do
    options = default_options(context.test)
    File.touch!(options[:devpath])

    start_sshd(options)
    fw_contents = Fwup.create_corrupt_firmware()

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
    fw_contents = Fwup.create_firmware(task: "complete")

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
    fw_contents = Fwup.create_firmware(task: "complete")

    {output, exit_status} = do_ssh(fw_contents)

    assert exit_status != 0
    assert output =~ "Error: Invalid device path: \"\""
  end

  def precheck_custom_task(options) do
    {:ok, options}
  end

  def precheck_fail() do
    :error
  end

  test "precheck can change the task to run", context do
    options =
      default_options(context.test) ++
        [precheck: {__MODULE__, :precheck_custom_task, [[task: "custom"]]}]

    File.touch!(options[:devpath])

    start_sshd(options)
    fw_contents = Fwup.create_firmware(task: "custom")

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

  test "precheck can stop an update", context do
    options = default_options(context.test) ++ [precheck: {__MODULE__, :precheck_fail, []}]

    File.touch!(options[:devpath])

    start_sshd(options)
    fw_contents = Fwup.create_firmware()

    {output, exit_status} = do_ssh(fw_contents)

    assert exit_status != 0
    assert output =~ "Error: precheck failed"
  end
end
