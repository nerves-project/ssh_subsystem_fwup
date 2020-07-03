# SSHSubsystemFwup

[![CircleCI](https://circleci.com/gh/nerves-project/ssh_subsystem_fwup/tree/main.svg?style=svg)](https://circleci.com/gh/nerves-project/ssh_subsystem_fwup/tree/main)
[![Hex version](https://img.shields.io/hexpm/v/ssh_subsystem_fwup.svg "Hex version")](https://hex.pm/packages/ssh_subsystem_fwup)

This library provides an [ssh](https://en.wikipedia.org/wiki/Secure_Shell)
subsystem that applies Nerves "over-the-air" firmware updates. This is a
breaking update to
[`ssh_subsystem_fwup`](https://github.com/nerves-project/ssh_subsystem_fwup)
that extracts the update service to be a `:ssh.daemon/1` spec. This removes
quite a bit of code and makes it possible to:

1. More easily customize ssh authentication (for example, password-based auth is
   possible)
2. Handle host keys differently and more securely
3. Run firmware updates on port 22 with other ssh services

In addition, the protocol for sending updates over ssh has been simplified. If
you're coming from `ssh_subsystem_fwup`, you'll likely have used the
`upload.sh` script so this will be transparent. If you wrote your own script,
you'll need to delete some lines of code from it.

## Installation

First, add `ssh_subsystem_fwup` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:ssh_subsystem_fwup, "~> 0.4.0"}]
end
```

Then add ssh subsystem spec to the call that starts the `ssh` daemon. This code
will look something like:

```elixir
    {:ok, ref} =
      :ssh.daemon([
        {:subsystems, [SSHSubsystemFwup.subsystem_spec()]}
      ])
```

You will likely have many more options passed to the `ssh.daemon`.

## Uploading firmware

To upload a firmware file, go to your Nerves project and run:

```shell
mix firmware.gen.script
```

This should create an `upload.sh` script that has a few conveniences to make
uploading Nerves firmware easier. You can frequently run `./upload.sh` without
arguments. To specify which device to upload to, pass the devices hostname as
the first argument. For example:

```shell
$ ./upload.sh nerves-1234.local
fwup: Upgrading partition B
|====================================| 100% (32.34 / 32.34) MB
Success!
Elapsed time: 4.720 s
Disconnected from 172.31.207.89 port 22
```

Note that the `.local` address assumes that mDNS has been configured on the
device and that mDNS works on your network and OS. That's not always the case
and a frequent source of frustration when it fails. When in doubt, check that
you can upload to the device's IP address. You can get the IP address from your
router or by connecting to the device's IEx prompt and running `ifconfig`.

## Upload protocol

It's not necessary to use the `upload.sh` script. The following line is
equivalent:

```shell
cat $firmware | ssh -s $nerves_device fwup
```

## License

All source code is licensed under the
[Apache License, 2.0](https://opensource.org/licenses/Apache-2.0).
