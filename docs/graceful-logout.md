# Graceful logout

The configured logout shortcut opens a shared GTK confirmation for Oxbow/ReKa.
Cancel is initially selected when application windows exist. Accepting requests
normal closure once for each original window; applications can save, prompt or
refuse. The monitor retains new windows/dialogs without repeatedly closing them.
UWSM stops the session only after no application windows remain.

Cancel preserves the remaining session but cannot reopen already closed apps.
Force quit requires a second explicit confirmation and may lose unsaved work.
There is no automatic forced logout or PID guessing from titles/app IDs.

Optional response monitoring distinguishes a timeout from an app waiting for a
save decision. Its module option documents compositor support and fallback;
monitoring never forces logout.

`graceful-logout` drives real manager windows, native save prompts, cancellation
and force confirmation in private VMs. `graceful-logout-health` additionally
checks observer timeout and recovery with the candidate compositor bridge.
Neither closes host windows or ends the host session.
