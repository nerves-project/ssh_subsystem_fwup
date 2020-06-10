defmodule NervesFirmwareSSH2.Fwup do
  use GenServer
  require Logger

  @moduledoc false

  @type options :: [cm: pid(), fwup_path: Path.t(), devpath: Path.t(), task: String.t()]

  @spec start_link(options()) :: GenServer.on_start()
  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @spec send_chunk(GenServer.server(), binary()) :: :ok | :error
  def send_chunk(pid, chunk) do
    GenServer.call(pid, {:send, chunk})
  end

  @impl true
  def init(options) do
    cm = Keyword.fetch!(options, :cm)
    Process.monitor(cm)
    fwup_path = Keyword.get(options, :fwup_path) || System.find_executable("fwup")
    fwup_extra_options = Keyword.get(options, :fwup_extra_options, [])
    devpath = Keyword.get(options, :devpath, "/dev/mmcblk0")
    task = Keyword.get(options, :task, "upgrade")

    Process.flag(:trap_exit, true)

    args = [
      "--exit-handshake",
      "--apply",
      "--no-unmount",
      "-d",
      devpath,
      "--task",
      task | fwup_extra_options
    ]

    port =
      Port.open({:spawn_executable, fwup_path}, [
        {:args, args},
        :use_stdio,
        :binary,
        :exit_status
      ])

    {:ok, %{port: port, cm: cm, done: false}}
  end

  @impl true
  def handle_call(_cmd, _from, %{done: true} = state) do
    # In the process of closing down, so just ignore these.
    {:reply, :error, state}
  end

  def handle_call({:send, chunk}, _from, state) do
    # Since fwup may be slower than ssh, we need to provide backpressure
    # here. It's tricky since `Port.command/2` is the only way to send
    # bytes to fwup synchronously, but it's possible for fwup to error
    # out when it's sending. If fwup errors out, then we need to make
    # sure that a message gets back to the user for what happened.
    # `Port.command/2` exits on error (it will be an :epipe error).
    # Therefore we start a new process to call `Port.command/2` while
    # we continue to handle responses. We also trap_exit to get messages
    # when the port the Task exit.
    result =
      try do
        Port.command(state.port, chunk)
        :ok
      rescue
        ArgumentError ->
          Logger.info("Port.command ArgumentError race condition detected and handled")
          :error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(_message, %{done: true} = state) do
    {:noreply, state}
  end

  def handle_info({port, {:data, response}}, %{port: port} = state) do
    # fwup says that it's going to exit by sending a CTRL+Z (0x1a)
    case String.split(response, "\x1a", parts: 2) do
      [response] ->
        :ssh_channel.cast(state.cm, {:fwup_data, response})
        {:noreply, state}

      [response, <<status>>] ->
        # fwup exited with status
        Logger.info("fwup exited with status #{status}")
        close_port(port)
        :ssh_channel.cast(state.cm, {:fwup_data, response})
        :ssh_channel.cast(state.cm, {:fwup_exit, status})
        {:noreply, %{state | done: true}}

      [response, other] ->
        # fwup exited without status
        Logger.info("fwup exited improperly: #{inspect(other)}")
        close_port(port)
        :ssh_channel.cast(state.cm, {:fwup_data, response})
        {:noreply, %{state | done: true}}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("fwup exited with status #{status} without handshaking")
    :ssh_channel.cast(state.cm, {:fwup_exit, status})
    {:noreply, %{state | done: true}}
  end

  def handle_info({port, :closed}, %{port: port} = state) do
    Logger.info("fwup port was closed")
    :ssh_channel.cast(state.cm, {:fwup_exit, 0})
    {:noreply, %{state | done: true}}
  end

  def handle_info({:DOWN, _, :process, cm, _reason}, %{cm: cm, port: port} = state) do
    Logger.info("firmware ssh handler exited before fwup could finish")
    close_port(port)
    {:noreply, %{state | done: true}}
  end

  defp close_port(port) do
    send(port, {self(), :close})
  end
end
