# Changelog

## v0.5.0

Initial release.

This factors out the SSH subsystem from
[`nerves_firmware_ssh`](https://github.com/nerves-project/nerves_firmware_ssh)
and removes all ssh server code. The user of this library now has to start a
server themselves. This makes it possible to run the firmware update on port 22
and removes the constraint of needing to hard code authorized ssh public keys.
