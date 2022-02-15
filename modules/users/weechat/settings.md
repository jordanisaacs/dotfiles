# Weechat Settings

Will keep updated with settings

```
/set irc.look.server_buffer independent
```

## Secrets

Generate passphrase

On command line store passphrase in secret store

```
secret-tool store --label='Weechat Passphrase' irc weechat type passphrase
```

Auto-login

```
/secure passphrase *******
/set sec.crypt.passphrase_command secret-tool lookup irc weechat type passphrase
```

## Libera

General settings

```
/set irc.server.libera.addresses irc.libera.chat/6697
/set irc.server.libera.autoconnect on
/set irc.server.libera.nicks *****
/set irc.server.libera.realname *****
/set irc.server.libera.username *****
```

SASL. Set `libera_password` to the nickserv password.

```
/secure set libera_password *******
/set irc.server.libera.sasl_mechanism plain
/set irc.server.libera.sasl_password ${sec.data.libera_password}
```
