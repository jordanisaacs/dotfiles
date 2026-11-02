;;; Minimal window-manager session, independent of the user's editor config.

(require 'reka)
(require 'reka-simulation)
(require 'server)
(require 'tab-bar)

(defconst jd-reka-settings
  (with-temp-buffer
    (insert-file-contents jd-reka-settings-file)
    (json-parse-buffer :object-type 'alist :array-type 'list)))

(setq server-name "reka"
      inhibit-startup-screen t
      initial-scratch-message nil
      use-dialog-box nil
      confirm-kill-processes nil
      reka-floating-toggle-key "s-SPC"
      tab-bar-show 1
      tab-bar-new-tab-choice "*reka-background*")

(set-face-attribute 'default nil
                    :family (alist-get 'monospaceFont jd-reka-settings)
                    :height (* 10 (alist-get 'uiFontSize jd-reka-settings)))
(load-theme 'modus-vivendi t)
(dolist (face '(variable-pitch mode-line mode-line-inactive tab-bar tab-bar-tab tab-bar-tab-inactive))
  (set-face-attribute face nil
                      :family (alist-get 'uiFont jd-reka-settings)
                      :height (* 10 (alist-get 'uiFontSize jd-reka-settings))))
(tab-bar-mode 1)
(tab-bar-rename-tab "1")
(get-buffer-create "*reka-background*")

(defun jd-reka-command (command)
  "Run a declaratively configured COMMAND without a command shell."
  ;; A launcher can exit before its app-start helper. Closing a PTY then sends
  ;; SIGHUP to that helper before it can hand the application to systemd.
  (let* ((process-connection-type nil)
         (process (apply #'start-process "reka-command" " *reka-command*" command)))
    (set-process-query-on-exit-flag process nil)))

(defun jd-reka-bind (key command)
  "Register global KEY to invoke the Emacs COMMAND."
  (global-set-key (kbd key) command)
  (add-to-list 'reka-intercept-prefixes key))

(defun jd-reka-close-window ()
  "Request a normal close of the active native application."
  (interactive)
  (when-let* ((buffer (reka--active-application-buffer)))
    (reka-request-close buffer)))

(defun jd-reka-workspace (number)
  "Select or create the workspace NUMBER."
  (while (< (length (tab-bar-tabs)) number)
    (tab-bar-new-tab)
    (tab-bar-rename-tab (number-to-string (length (tab-bar-tabs)))))
  (tab-bar-select-tab number))

(dolist (binding (alist-get 'commands jd-reka-settings))
  (unless (memq (car binding) '(launcher quit))
    (let ((command (cdr binding)))
      (jd-reka-bind (symbol-name (car binding))
                    (lambda () (interactive) (jd-reka-command command))))))
(jd-reka-bind (alist-get 'launcherKey jd-reka-settings)
              (lambda () (interactive)
                (jd-reka-command (alist-get 'launcher (alist-get 'commands jd-reka-settings)))))
(defun jd-reka-quit ()
  (interactive)
  (jd-reka-command (alist-get 'quit (alist-get 'commands jd-reka-settings))))
(jd-reka-bind "s-S-q" #'jd-reka-quit)
(global-set-key (kbd "C-x C-c")
                (lambda () (interactive)
                  (user-error "Use Super+Shift+q to end the desktop session")))
(jd-reka-bind "s-S-c" #'jd-reka-close-window)
(jd-reka-bind (alist-get 'nextKey jd-reka-settings) #'other-window)
(jd-reka-bind (alist-get 'previousKey jd-reka-settings)
              (lambda () (interactive) (other-window -1)))
(jd-reka-bind "s-m" #'delete-other-windows)
(jd-reka-bind "s-t" #'balance-windows)
(dotimes (index 9)
  (let ((number (1+ index)))
    (jd-reka-bind (format "s-%d" number)
                  (lambda () (interactive) (jd-reka-workspace number)))))

(defun jd-reka-ready ()
  "Publish readiness after the compositor has processed the first usable frame."
  (let* ((command (alist-get 'setup jd-reka-settings))
         (status (apply #'call-process (car command) nil " *reka-setup*" nil (cdr command))))
    (unless (zerop status)
      (error "UWSM could not finalize the Reka session: %s" status))))
(add-hook 'reka-ready-hook #'jd-reka-ready)
(server-start)
(reka-enable)
(reka-push-intercept-prefix "s-f" 'toggle-fullscreen)
