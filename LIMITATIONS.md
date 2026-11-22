# Limitations

What the bar plugin cannot do, and what to do about it. Back to the [README](README.md).

The daemon has limits of its own, such as the NVIDIA effects needing an RTX GPU. They are in the daemon's [LIMITATIONS.md](https://github.com/rsd/omarchy-broadcast/blob/main/LIMITATIONS.md).

## English only

There is no translation catalogue.

## One application at a time on the virtual camera

The virtual camera serves one application at a time. The cause and the workaround are in [Troubleshooting](docs/troubleshooting.md#another-app-says-the-camera-is-busy).

## Telling active from idle

The `active` state uses the theme's accent colour, so it is distinguished from `idle` by the icon shape and colour together.

## Camera names lose markup characters

Camera names are shown as the daemon reports them, after removing markup characters such as `&`, `<` and `>`.

## Long microphone node names

The input device dropdown offers a microphone only by a PipeWire node name of at most 128 characters, the longest option value the CLI's JSON carries. A longer name arrives shortened and is not offered, and while it is the one in use the dropdown shows no choice selected. Choose such a microphone from a terminal instead:

```sh
omarchy-broadcast mic device <node name>
```
