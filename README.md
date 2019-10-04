# NervesFirmwareSSH2

[![CircleCI](https://circleci.com/gh/nerves-project/nerves_firmware_ssh2/tree/master.svg?style=svg)](https://circleci.com/gh/nerves-project/nerves_firmware_ssh2/tree/master)
[![Hex version](https://img.shields.io/hexpm/v/nerves_firmware_ssh2.svg "Hex version")](https://hex.pm/packages/nerves_firmware_ssh2)

This library provides an [ssh](https://en.wikipedia.org/wiki/Secure_Shell)
subsystem that applies Nerves "over-the-air" firmware updates.

## Installation

First, add `nerves_firmware_ssh2` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:nerves_firmware_ssh2, "~> 0.4.0"}]
end
```

Then add ssh subsystem spec to the call that starts the `ssh` daemon. This code
will look something like:

```elixir
    {:ok, ref} =
      :ssh.daemon([
        {:subsystems, [NervesFirmwareSSH2.subsystem_spec()]}
      ])
```

You will likely have many more options passed to the `ssh.daemon`.

## Uploading firmware

To upload a firmware file, send the contents of that file to the
`nerves_firmware_ssh2` subsystem. For example,

```shell
cat my_app.fw | ssh -s <target_ip_addr> nerves_firmware_ssh2
```

## License

All source code is licensed under the
[Apache License, 2.0](https://opensource.org/licenses/Apache-2.0).
