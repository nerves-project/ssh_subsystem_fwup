defmodule NervesFirmwareSSH2.Handler do
  @behaviour :ssh_client_channel
  require Logger

  @moduledoc false

  alias NervesFirmwareSSH2.Fwup

  defmodule State do
    @moduledoc false
    defstruct state: :running_fwup,
              id: nil,
              cm: nil,
              fwup: nil,
              options: []
  end

  @impl true
  def init(options) do
    combined_options = Keyword.merge(default_options(), options)

    {:ok, %State{options: combined_options}}
  end

  defp default_options() do
    [
      devpath: Nerves.Runtime.KV.get("nerves_fw_devpath"),
      fwup_path: System.find_executable("fwup"),
      fwup_extra_options: [],
      task: "upgrade",
      success_callback: {Nerves.Runtime, :reboot, []}
    ]
  end

  @impl true
  def handle_msg({:ssh_channel_up, channel_id, cm}, state) do
    Logger.debug("nerves_firmware_ssh2: new connection")
    {:ok, fwup} = Fwup.start_link([cm: self()] ++ state.options)

    {:ok, %{state | id: channel_id, cm: cm, fwup: fwup}}
  end

  @impl true
  def handle_ssh_msg({:ssh_cm, _cm, {:data, _channel_id, 0, data}}, state) do
    process_message(state.state, data, state)
  end

  def handle_ssh_msg({:ssh_cm, _cm, {:data, _channel_id, 1, _data}}, state) do
    # Ignore stderr
    {:ok, state}
  end

  def handle_ssh_msg({:ssh_cm, _cm, {:eof, _channel_id}}, state) do
    {:ok, state}
  end

  def handle_ssh_msg({:ssh_cm, _cm, {:signal, _, _}}, state) do
    # Ignore signals
    {:ok, state}
  end

  def handle_ssh_msg({:ssh_cm, _cm, {:exit_signal, _channel_id, _, _error, _}}, state) do
    {:stop, :normal, state}
  end

  def handle_ssh_msg({:ssh_cm, _cm, {:exit_status, _channel_id, _status}}, state) do
    {:stop, :normal, state}
  end

  def handle_ssh_msg({:ssh_cm, _cm, message}, state) do
    Logger.debug("Ignoring handle_ssh_msg #{inspect(message)}")
    {:ok, state}
  end

  @impl true
  def handle_call(_request, _from, state) do
    {:reply, :error, state}
  end

  @impl true
  def handle_cast({:fwup_data, response}, state) do
    case :ssh_connection.send(state.cm, state.id, response) do
      :ok -> {:noreply, state}
      {:error, _reason} -> {:stop, :normal, state}
    end
  end

  def handle_cast({:fwup_exit, rc}, state) do
    # Successful run of fwup.
    Logger.debug("nerves_firmware_ssh2: rc=#{rc}")
    _ = :ssh_connection.send_eof(state.cm, state.id)
    _ = :ssh_connection.exit_status(state.cm, state.id, rc)

    run_callback(rc, state.options[:success_callback])

    {:stop, :normal, state}
  end

  defp run_callback(0 = _rc, {m, f, a}) do
    # Let others know that fwup was successful. The usual operation
    # here is to reboot. Run the callback in its own process so that
    # any issues with it don't affect processing here.
    spawn(m, f, a)
  end

  defp run_callback(_rc, _mfa), do: :ok

  @impl true
  def terminate(_reason, _state) do
    Logger.debug("nerves_firmware_ssh2: connection terminated")
    :ok
  end

  @impl true
  def code_change(_old, state, _extra) do
    {:ok, state}
  end

  defp process_message(:running_fwup, data, state) do
    case Fwup.send_chunk(state.fwup, data) do
      :ok ->
        {:ok, state}

      _ ->
        # Error - need to wait for fwup to exit so that we can
        # report back anything that it may say
        new_state = %{state | state: :wait_for_fwup_error}

        {:ok, new_state}
    end
  end

  defp process_message(:wait_for_fwup_error, _data, state) do
    # Just discard anything we get
    {:ok, state}
  end
end
