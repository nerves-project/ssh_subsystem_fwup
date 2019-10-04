defmodule NervesFirmwareSSH2.Handler do
  require Logger

  @moduledoc false

  alias NervesFirmwareSSH2.Fwup

  defmodule State do
    @moduledoc false
    defstruct state: :running_commands,
              id: nil,
              cm: nil,
              fwup: nil,
              fwup_options: [],
              success_callback: nil
  end

  # See http://erlang.org/doc/man/ssh_channel.html for API

  def init(options) do
    _ = Logger.debug("nerves_firmware_ssh2: initialized")

    success_callback = Keyword.get(options, :success_callback, {Nerves.Runtime, :reboot, []})

    {:ok, %State{success_callback: success_callback, fwup_options: options}}
  end

  def handle_msg({:ssh_channel_up, channel_id, connection_manager}, state) do
    _ = Logger.debug("nerves_firmware_ssh2: new connection")
    {:ok, fwup} = Fwup.start_link([cm: self()] ++ state.fwup_options)

    {:ok, %{state | id: channel_id, cm: connection_manager, fwup: fwup}}
  end

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

  def handle_ssh_msg({:ssh_cm, _cm, {:exit_signal, channel_id, _, _error, _}}, state) do
    {:stop, channel_id, state}
  end

  def handle_ssh_msg({:ssh_cm, _cm, {:exit_status, channel_id, _status}}, state) do
    {:stop, channel_id, state}
  end

  def handle_ssh_msg({:ssh_cm, _cm, _message}, state) do
    {:ok, state}
  end

  def handle_cast({:fwup_data, response}, state) do
    case :ssh_connection.send(state.cm, state.id, response) do
      :ok -> {:noreply, state}
      {:error, reason} -> {:stop, reason, state}
    end
  end

  def handle_cast({:fwup_exit, 0}, state) do
    # Successful run of fwup.
    _ = Logger.debug("nerves_firmware_ssh2: success")
    _ = :ssh_connection.send_eof(state.cm, state.id)
    _ = :ssh_connection.exit_status(state.cm, state.id, 0)

    # Let others know that fwup was successful. The usual operation
    # here is to reboot.
    case state.success_callback do
      {m, f, a} -> apply(m, f, a)
      _ -> :ok
    end

    {:stop, state.id, state}
  end

  def handle_cast({:fwup_exit, rc}, state) do
    _ = :ssh_connection.send_eof(state.cm, state.id)
    _ = :ssh_connection.exit_status(state.cm, state.id, rc)

    {:stop, :fwup_error, state}
  end

  def terminate(_reason, _state) do
    _ = Logger.debug("nerves_firmware_ssh2: connection terminated")
    :ok
  end

  defp process_message(:running_commands, data, state) do
    case Fwup.send_chunk(state.fwup, data) do
      :ok ->
        {:ok, state}

      _ ->
        # Error - need to wait for fwup to exit so that we can
        # report back anything that it may say
        new_state = %{
          state
          | state: :wait_for_fwup_error
        }

        {:ok, new_state}
    end
  end

  defp process_message(:wait_for_fwup_error, _data, state) do
    # Just discard anything we get
    {:ok, state}
  end
end
