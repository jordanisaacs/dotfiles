# Weechat Settings

Will keep updated with settings.

## General settings

```
/set irc.look.server_buffer independent
/set plugins.var.python.autojoin.autosave = on
```

## Libera

General settings

```
/server add libera irc.libera.chat/6697
/set irc.server.libera.autoconnect on
```

Set names

```
/set irc.server.libera.nicks *****
/set irc.server.libera.realname *****
/set irc.server.libera.username *****
```

SASL. Set `libera_password` to the nickserv password. First store password in keyring:

```
secret-tool store --label='Weechat Passphrase' irc weechat type passphrase
```

Now can use for auto decryption.

```
/secure set libera_password *******
/secure passphrase *******
/set sec.crypt.passphrase_command secret-tool lookup irc weechat type passphrase
/set irc.server.libera.sasl_mechanism plain
/set irc.server.libera.sasl_password ${sec.data.libera_password}
```
