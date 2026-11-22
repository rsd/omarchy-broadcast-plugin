# Install the Omarchy Broadcast bar plugin

Install the daemon first, then add the plugin to the Omarchy shell and enable it. The plugin needs no root and installs no packages.

Not sure whether the plugin is for you? Read the [README](README.md) first.

## Before you start

You need Omarchy and the omarchy-broadcast daemon, installed and running. The plugin is a client of the daemon and does not include it. Nothing in this repository installs it.

Install the daemon with its own guide, the [daemon's INSTALL.md](https://github.com/rsd/omarchy-broadcast/blob/main/INSTALL.md). Follow it through its [Check that it works](https://github.com/rsd/omarchy-broadcast/blob/main/INSTALL.md#check-that-it-works) section, then come back here. The daemon is ready when this command prints its state:

```sh
omarchy-broadcast status
```

Keep the daemon and the plugin up to date together. When one of them is too old for a feature, the panel says which one to update.

## Install the plugin

Install it from the Omarchy plugin marketplace listing, or add it by hand from its git URL:

```sh
omarchy plugin add https://github.com/rsd/omarchy-broadcast-plugin
```

The command shows a warning that plugins run as unsandboxed code in the shell and asks you to confirm. Then it clones the repository into `~/.config/omarchy/plugins/br.com.dias.omarchy-broadcast`, validates it and asks the shell to rescan.

## Enable the plugin on the bar

Enable the plugin. This also places the icon in the right section of the bar:

```sh
omarchy plugin enable br.com.dias.omarchy-broadcast
```

To choose the place yourself, pass a placement to `enable`, or move the icon later:

```sh
omarchy bar move br.com.dias.omarchy-broadcast --section centerBegin --index 0
omarchy bar put  br.com.dias.omarchy-broadcast --after omarchy.clock
```

You can also add and enable in one step:

```sh
omarchy plugin add https://github.com/rsd/omarchy-broadcast-plugin --enable
```

## The CLI path

The plugin finds `omarchy-broadcast` on the shell's `PATH`. If it is not there, set the `cliPath` setting to its absolute path ([Configuration](docs/panel.md#configuration)). If you install the CLI after the plugin, reload the shell.

## Check that it works

1. Confirm that the shell found the plugin:

   ```sh
   omarchy plugin list
   ```

   The list shows `br.com.dias.omarchy-broadcast`.

2. Look at the bar icon. A webcam icon means the plugin talks to the daemon (a crossed-out webcam means the camera is off). A warning sign means it does not: see [Troubleshooting](docs/troubleshooting.md).

3. Left click the icon. The panel opens with the preview strip, the Effects, Camera and Mic tabs and the camera's state in its header.

## Update

For a plugin added with the add command, or linked from a git checkout ([Running from a local checkout](docs/development.md#running-from-a-local-checkout)):

```sh
omarchy plugin update br.com.dias.omarchy-broadcast
```

The command fetches the repository, shows the changes, asks for confirmation, fast-forwards and validates the result. A copy made without `.git` has nothing to pull from: copy it again ([Running from a local checkout](docs/development.md#running-from-a-local-checkout)). The plugin's version is the `version` field of `manifest.json`.

The plugin reads a fixed interface, not a version number: see [Versioning](docs/development.md#versioning).

## Uninstall

```sh
omarchy plugin disable br.com.dias.omarchy-broadcast
omarchy plugin remove br.com.dias.omarchy-broadcast
```

If a placement is left in the bar layout, remove it with the shell's bar commands and reload the shell. They are listed by:

```sh
omarchy bar --help
```

The plugin starts no service of its own and writes no files. The one exception is that the shell stores your choices in the panel (the preview's shown or hidden state and rate, and the tab) in the plugin's bar-layout entry.

Removing the plugin does not touch the daemon. To remove the daemon too, see the [Uninstall section of its INSTALL.md](https://github.com/rsd/omarchy-broadcast/blob/main/INSTALL.md#uninstall).

## If something does not work

The messages the bar icon and the panel show, with their causes and what to do, are in [docs/troubleshooting.md](docs/troubleshooting.md).
